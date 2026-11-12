"""Download KBO official snapshots and reconcile with provider aggregates."""
import argparse
import hashlib
import json
import re
import time
import threading
from concurrent.futures import ThreadPoolExecutor
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta
from html.parser import HTMLParser
from http.cookiejar import CookieJar
from pathlib import Path
from urllib.parse import urlencode, urljoin, urlparse, parse_qs
from urllib.request import Request, build_opener, HTTPCookieProcessor

if __package__:
    from .fetch_kbo import write_json
else:  # Also support python tools/reconcile_kbo.py
    from fetch_kbo import write_json

BASE = 'https://www.koreabaseball.com'


class Page(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.form = {}
        self.selects = {}
        self.selected = {}
        self.links = []
        self.tables = []
        self.select = self.option = self.table = self.row = self.cell = self.anchor = None
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'input' and a.get('name') and a.get('type') not in ('submit', 'button', 'image'):
            self.form[a['name']] = a.get('value', '')
        if tag == 'select':
            self.select = a.get('name')
            if self.select:
                self.selects[self.select] = []
        if tag == 'option' and self.select:
            self.option = {'value': a.get('value', ''), 'text': '', 'selected': 'selected' in a}
        if tag == 'table':
            self.table = {'attrs': a, 'rows': []}
        if tag == 'tr' and self.table is not None:
            self.row = []
        if tag in ('td', 'th') and self.row is not None:
            self.cell = {'text': '', 'links': [], 'tag': tag}
        if tag == 'a' and a.get('href'):
            a['text'] = ''
            self.links.append(a)
            self.anchor = a
            if self.cell is not None:
                self.cell['links'].append(a['href'])

    def handle_data(self, data):
        if self.anchor is not None:
            self.anchor['text'] += data
        if self.option is not None:
            self.option['text'] += data
        if self.cell is not None:
            self.cell['text'] += data

    def handle_endtag(self, tag):
        if tag == 'a':
            self.anchor = None
        if tag == 'option' and self.option is not None:
            self.selects[self.select].append(self.option)
            if self.select not in self.form or self.option['selected']:
                self.form[self.select] = self.option['value']
            if self.option['selected']:
                self.selected[self.select] = self.option['value']
            self.option = None
        if tag == 'select':
            self.select = None
        if tag in ('td', 'th') and self.cell is not None:
            self.cell['text'] = ' '.join(self.cell['text'].split())
            self.row.append(self.cell)
            self.cell = None
        if tag == 'tr' and self.row is not None:
            self.table['rows'].append(self.row)
            self.row = None
        if tag == 'table' and self.table is not None:
            self.tables.append(self.table)
            self.table = None

    def field(self, suffix):
        matches = [name for name in self.selects if name.endswith('$' + suffix)]
        if len(matches) != 1:
            raise ValueError(f'공식 페이지 선택 항목 식별 실패: {suffix}')
        return matches[0]


class OfficialClient:
    def __init__(self, root):
        self.root = root
        self.opener = build_opener(HTTPCookieProcessor(CookieJar()))
        self.sources = []
        self.last = 0
        self.locks = defaultdict(threading.Lock)

    def get(self, url, label, form=None):
        time.sleep(max(0, 0.6 - (time.monotonic() - self.last)))
        self.last = time.monotonic()
        body = urlencode(form).encode() if form is not None else None
        request = Request(url, data=body, headers={'User-Agent': 'Mozilla/5.0',
                          'Content-Type': 'application/x-www-form-urlencoded'})
        with self.opener.open(request, timeout=35) as response:
            raw = response.read()
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / f'{label}.html').write_bytes(raw)
        self.sources.append({'url': url, 'file': f'raw/{label}.html',
                             'fetched_at': datetime.now(timezone.utc).isoformat(),
                             'sha256': hashlib.sha256(raw).hexdigest()})
        return Page(raw.decode('utf-8-sig'))

    def regular(self, path, label, year):
        url = urljoin(BASE, path)
        page = self.get(url, label + '_initial')
        season = page.field('ddlSeason')
        series = page.field('ddlSeries')
        form = dict(page.form)
        form.update({season: str(year), series: '0', '__EVENTTARGET': series, '__EVENTARGUMENT': ''})
        page = self.get(url, label, form)
        if page.form.get(season) != str(year) or page.form.get(series) != '0':
            raise ValueError('공식 기록 시즌/정규시즌 선택 검증 실패')
        return page

    def public_json(self, path, params, destination):
        with self.locks[str(destination)]:
            return self._public_json(path, params, destination)

    def _public_json(self, path, params, destination):
        if destination.exists():
            return json.loads(destination.read_text(encoding='utf-8-sig'))
        time.sleep(max(0, 0.3 - (time.monotonic() - self.last)))
        self.last = time.monotonic()
        url = urljoin(BASE, path)
        request = Request(url, data=urlencode(params).encode(), headers={
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest', 'User-Agent': 'Mozilla/5.0',
            'Referer': BASE + '/Schedule/GameCenter/Main.aspx'})
        with self.opener.open(request, timeout=35) as response:
            raw = response.read()
        data = json.loads(raw.decode('utf-8-sig'))
        write_json(destination, data)
        return data


FEEDS = {
    'team_batting': '/Record/Team/Hitter/Basic1.aspx',
    'team_pitching': '/Record/Team/Pitcher/Basic1.aspx',
    'team_fielding': '/Record/Team/Defense/Basic.aspx',
    'team_running': '/Record/Team/Runner/Basic.aspx',
    'player_batting1': '/Record/Player/HitterBasic/Basic1.aspx?sort=GAME_CN',
    'player_batting2': '/Record/Player/HitterBasic/Basic2.aspx?sort=GAME_CN',
    'player_pitching1': '/Record/Player/PitcherBasic/Basic1.aspx?sort=GAME_CN',
    'player_pitching2': '/Record/Player/PitcherBasic/Basic2.aspx?sort=GAME_CN',
    'player_fielding': '/Record/Player/Defense/Basic.aspx?sort=GAME_CN',
    'player_running': '/Record/Player/Runner/Basic.aspx?sort=GAME_CN',
}


def table_rows(page):
    tables = [t for t in page.tables if any(c.startswith('tData') for c in t['attrs'].get('class', '').split())]
    if len(tables) != 1:
        raise ValueError(f'공식 통계 표를 하나로 식별하지 못했습니다: {len(tables)}개')
    rows = tables[0]['rows']
    headers = [c['text'] for c in rows[0]]
    result = []
    for cells in rows[1:]:
        if not cells or cells[0]['text'] in ('합계', '평균'):
            continue
        if len(cells) != len(headers):
            raise ValueError(f'공식 표 열 개수 불일치: {headers}, {cells}')
        row = {key: cell['text'] for key, cell in zip(headers, cells)}
        player_links = [urljoin(BASE, link) for c in cells for link in c['links'] if 'playerId=' in link]
        if '선수명' in row:
            ids = {parse_qs(urlparse(link).query)['playerId'][0] for link in player_links}
            if len(ids) != 1:
                raise ValueError('공식 선수 ID를 하나로 식별하지 못했습니다.')
            row['kbo_player_id'] = ids.pop()
        result.append(row)
    return result


def verify_filter(page, year):
    if page.form.get(page.field('ddlSeason')) != str(year) or page.form.get(page.field('ddlSeries')) != '0':
        raise ValueError('정규시즌/연도 필터 불일치')


def download(root, year):
    client = OfficialClient(root / 'raw')
    tables = {}
    for label, path in FEEDS.items():
        page = client.regular(path, label + '_001', year)
        collected, signatures = [], set()
        for number in range(1, 101):
            verify_filter(page, year)
            rows = table_rows(page)
            signature = json.dumps(rows, ensure_ascii=False, sort_keys=True)
            if signature in signatures:
                raise ValueError(f'공식 페이지 반복: {label}, {number}')
            signatures.add(signature)
            collected.extend(dict(row, source_file=f'raw/{label}_{number:03d}.html') for row in rows)
            if label.startswith('team_'):
                break
            hfpage = [v for k, v in page.form.items() if k.endswith('$hfPage')]
            if hfpage != [str(number)]:
                raise ValueError(f'공식 페이지 번호 불일치: {label}, {number}, {hfpage}')
            next_links = [a for a in page.links if 'ucPager' in a.get('id', '') and a.get('text', '').strip() == str(number + 1)]
            if not next_links:
                next_links = [a for a in page.links if a.get('id', '').endswith('ucPager_btnNext')]
            if not next_links:
                break
            target = re.search(r"__doPostBack\('([^']+)','([^']*)'\)", next_links[0]['href'])
            if target is None:
                raise ValueError('공식 페이지 이동 링크를 해석하지 못했습니다.')
            form = dict(page.form, __EVENTTARGET=target[1], __EVENTARGUMENT=target[2])
            page = client.get(urljoin(BASE, path), f'{label}_{number + 1:03d}', form)
        else:
            raise ValueError('공식 페이지 조회 상한 도달')
        tables[label] = collected
        write_json(root / 'official_tables_partial.json', {'season': year, 'series': '0', 'tables': tables})
        print(f'{label}: {len(collected)}행', flush=True)
    snapshot = {'season': year, 'series': '0', 'tables': tables, 'sources': client.sources,
                'fetched_at': datetime.now(timezone.utc).isoformat()}
    write_json(root / 'official_tables.json', snapshot)
    return snapshot


TEAM_NAMES = {'두산': '두산 베어스', '한화': '한화 이글스', 'KIA': 'KIA 타이거즈',
              'KT': 'KT 위즈', 'LG': 'LG 트윈스', '롯데': '롯데 자이언츠',
              'NC': 'NC 다이노스', '키움': '키움 히어로즈', '삼성': '삼성 라이온즈', 'SSG': 'SSG 랜더스'}
BATTING = {'G': 'games', 'PA': 'plate_appearances', 'AB': 'at_bats', 'R': 'runs',
           'H': 'hits', '2B': 'doubles', '3B': 'triples', 'HR': 'home_runs',
           'TB': 'total_bases', 'RBI': 'runs_batted_in', 'SAC': 'sacrifice_bunts',
           'SF': 'sacrifice_flies', 'BB': 'walks', 'IBB': 'intentional_walks',
           'HBP': 'hit_by_pitch', 'SO': 'batting_strikeouts', 'GDP': 'grounded_into_double_plays',
           'AVG': 'batting_average', 'OBP': 'on_base_percentage', 'SLG': 'slugging_percentage', 'OPS': 'ops'}
PITCHING = {'G': 'games', 'W': 'wins', 'L': 'losses', 'SV': 'saves', 'HLD': 'holds',
            'H': 'hits_allowed', 'HR': 'home_runs_allowed', 'BB': 'walks_allowed',
            'HBP': 'hit_batters', 'SO': 'pitcher_strikeouts', 'R': 'runs_allowed',
            'ER': 'earned_runs', 'ERA': 'earned_run_average', 'WHIP': 'whip',
            'CG': 'complete_games', 'SHO': 'shutouts', 'QS': 'quality_starts',
            'BSV': 'blown_saves', 'TBF': 'batters_faced', 'NP': 'pitches',
            '2B': 'doubles_allowed', '3B': 'triples_allowed', 'WP': 'wild_pitches', 'BK': 'balks'}
RATES = {'AVG', 'OBP', 'SLG', 'OPS', 'ERA', 'WHIP'}


def number(value, rate=False):
    if value in (None, '', '-'):
        return None
    text = value.replace(',', '')
    return float(text) if rate else int(text)


def official_outs(value):
    if value in (None, '', '-'):
        return None
    if value in ('1/3', '2/3'):
        return int(value[0])
    match = re.fullmatch(r'(\d+)(?:\s+([12])/3)?', value)
    if not match:
        raise ValueError(f'공식 이닝 표기를 해석할 수 없습니다: {value}')
    return int(match[1]) * 3 + int(match[2] or 0)


def normalized(row, mapping):
    result = {name: number(row[column], column in RATES) for column, name in mapping.items() if column in row}
    if 'IP' in row:
        outs = official_outs(row['IP'])
        result['outs_pitched'] = outs
        result['innings_pitched'] = f'{outs // 3}.{outs % 3}' if outs is not None else None
    return result


def merged_by_id(first, second):
    a = {r['kbo_player_id']: r for r in first}
    b = {r['kbo_player_id']: r for r in second}
    if len(a) != len(first) or len(b) != len(second) or set(a) != set(b):
        raise ValueError('공식 기본/추가 기록 선수 ID 집합이 다르거나 중복됩니다.')
    result = []
    for pid, row in a.items():
        other = b[pid]
        for key in ('선수명', '팀명'):
            if row[key] != other[key]:
                raise ValueError(f'공식 선수 ID의 이름/팀 충돌: {pid}')
        overlap = set(row) & set(other) - {'순위', 'source_file'}
        if any(row[key] != other[key] for key in overlap):
            raise ValueError(f'공식 기본/추가 표 중복 필드 충돌: {pid}')
        result.append(dict(row, **other, source_files=[row['source_file'], other['source_file']]))
    return result


def reconcile(folder, snapshot):
    root = folder / 'official'
    source = json.loads((folder / 'teams.json').read_text(encoding='utf-8'))
    if snapshot['series'] != '0' or str(snapshot['season']) != str(source['season']['year']):
        raise ValueError('공식 스냅샷 시즌/경기 종류 불일치')
    tables = snapshot['tables']
    by_name = {t['name']: t for t in source['competitors']}
    official_teams = {}
    for label in ('team_batting', 'team_pitching', 'team_fielding', 'team_running'):
        if len(tables[label]) != 10 or {r['팀명'] for r in tables[label]} != set(TEAM_NAMES):
            raise ValueError('공식 팀 기록 10개 팀 확보 검증 실패')
        for row in tables[label]:
            short = row['팀명']
            team = official_teams.setdefault(short, {'team_id': by_name[TEAM_NAMES[short]]['id'],
                                                     'team_name': TEAM_NAMES[short], 'official_team_name': short,
                                                     'source_files': []})
            team['source_files'].append(row['source_file'])
            if label == 'team_batting':
                team['batting'] = normalized(row, BATTING)
            elif label == 'team_pitching':
                team['pitching'] = normalized(row, PITCHING)
            elif label == 'team_fielding':
                team['fielding'] = {'errors': number(row['E'])}
            elif label == 'team_running':
                team['running'] = {'stolen_bases': number(row['SB']), 'caught_stealing': number(row['CS'])}
    for team in official_teams.values():
        pitching, batting = team['pitching'], team['batting']
        g, w, losses = pitching['games'], pitching['wins'], pitching['losses']
        if batting['games'] != g:
            raise ValueError('공식 팀 타격/투구 경기 수 불일치')
        team.update(games=g, wins=w, losses=losses, ties=g-w-losses,
                    runs_scored=batting['runs'], runs_allowed=pitching['runs_allowed'])

    official_players = {}

    def add(row, role, stats):
        pid = row['kbo_player_id']
        player = official_players.setdefault(pid, {'player_id': f'kbo:player:{pid}', 'kbo_player_id': pid,
                                                  'player_name': row['선수명'], 'official_team_names': [],
                                                  'source_files': [], 'batting': None, 'pitching': None,
                                                  'fielding_by_position': [], 'running': None})
        if player['player_name'] != row['선수명']:
            raise ValueError(f'동일 KBO ID의 이름 불일치: {pid}')
        if row['팀명'] not in player['official_team_names']:
            player['official_team_names'].append(row['팀명'])
        player['source_files'].extend(row.get('source_files', [row['source_file']]))
        if role == 'fielding_by_position':
            if any(r['position'] == stats['position'] for r in player[role]):
                raise ValueError(f'중복 공식 수비 포지션 기록: {pid}')
            player[role].append(stats)
        else:
            if player[role] is not None:
                raise ValueError(f'중복 공식 선수 기록: {pid}, {role}')
            player[role] = stats

    for row in merged_by_id(tables['player_batting1'], tables['player_batting2']):
        add(row, 'batting', normalized(row, BATTING))
    for row in merged_by_id(tables['player_pitching1'], tables['player_pitching2']):
        add(row, 'pitching', normalized(row, PITCHING))
    for row in tables['player_fielding']:
        add(row, 'fielding_by_position', {'position': row['POS'], 'games': number(row['G']),
                                         'starts': number(row['GS']), 'errors': number(row['E']),
                                         'outs_fielded': official_outs(row['IP'])})
    for row in tables['player_running']:
        add(row, 'running', {'stolen_bases': number(row['SB']), 'caught_stealing': number(row['CS'])})

    for player in official_players.values():
        player['source_files'] = sorted(set(player['source_files']))
    existing_teams = json.loads((folder / 'aggregated/team_season_stats.json').read_text(encoding='utf-8'))['teams']
    existing_players = json.loads((folder / 'aggregated/player_season_stats.json').read_text(encoding='utf-8'))['players']
    # Official data is authoritative under KBO IDs. Cross-provider name candidates
    # are deliberately not promoted into a verified ID mapping.
    team_differences = []
    comparisons = [('at_bats', 'batting', 'at_bats'), ('hits', 'batting', 'hits'),
                   ('home_runs', 'batting', 'home_runs'), ('runs_batted_in', 'batting', 'runs_batted_in'),
                   ('runs', 'batting', 'runs'), ('earned_runs', 'pitching', 'earned_runs'),
                   ('hits_allowed', 'pitching', 'hits_allowed'), ('walks_allowed', 'pitching', 'walks_allowed'),
                   ('saves', 'pitching', 'saves'), ('outs_pitched', 'pitching', 'outs_pitched'),
                   ('errors', 'fielding', 'errors'), ('stolen_bases', 'running', 'stolen_bases')]
    matched_fields = 0
    for old in existing_teams:
        new = next(t for t in official_teams.values() if t['team_id'] == old['team_id'])
        for field in ('games', 'wins', 'losses', 'ties', 'runs_scored', 'runs_allowed'):
            if old[field] != new[field]:
                team_differences.append({'team_id': old['team_id'], 'team_name': old['team_name'],
                                         'field': field, 'before': old[field], 'after': new[field]})
            else:
                matched_fields += 1
        for old_field, role, field in comparisons:
            before, after = old['observed_statistics'].get(old_field), new[role][field]
            if before != after:
                team_differences.append({'team_id': old['team_id'], 'team_name': old['team_name'],
                                         'field': f'{role}.{field}', 'before': before, 'after': after})
            else:
                matched_fields += 1

    name_index = defaultdict(set)
    for pid, player in official_players.items():
        for team_name in player['official_team_names']:
            name_index[(player['player_name'], team_name)].add(pid)
    candidates = []
    player_differences = []
    for old in existing_players:
        short = next(k for k, v in TEAM_NAMES.items() if v == old['team_name'])
        compact = re.sub(r'[,\s]', '', old['player_name'])
        names = {compact}
        if ',' in old['player_name']:
            names.add(old['player_name'].split(',')[0].strip())
        if re.fullmatch('[가-힣]{3}', compact):
            names.add(compact[-1] + compact[:-1])  # Candidate only: given-name/family-name ordering varies.
        ids = set().union(*(name_index.get((name, short), set()) for name in names))
        item = {'provider_player_id': old['player_id'], 'provider_team_id': old['team_id'],
                'provider_name': old['player_name'], 'team_name': old['team_name'],
                'candidate_kbo_player_ids': sorted(ids), 'verified_id_mapping': False,
                'status': 'unique_candidate' if len(ids) == 1 else 'ambiguous' if ids else 'unmatched'}
        candidates.append(item)
        if len(ids) != 1:
            continue
        candidate = official_players[next(iter(ids))]
        item['candidate_name'] = candidate['player_name']
        item['auto_applied_to_provider_id'] = False
        # Comparisons are provisional until identity and transfer scope are confirmed.
        for old_field, role, field in comparisons:
            group = candidate.get(role)
            if role == 'fielding':
                group = {'errors': sum(r['errors'] for r in candidate['fielding_by_position'])} if candidate['fielding_by_position'] else None
            if not group or field not in group:
                continue
            before, after = old['observed_statistics'].get(old_field), group[field]
            if before != after:
                player_differences.append({'provider_player_id': old['player_id'], 'provider_team_id': old['team_id'],
                                           'candidate_kbo_player_id': candidate['kbo_player_id'],
                                           'field': f'{role}.{field}', 'before': before, 'official_season_value': after,
                                           'status': 'candidate_difference_not_auto_applied'})
    metadata = {
        'updated_at': datetime.now(timezone.utc).isoformat(), 'season': source['season'],
        'record_scope': 'official_kbo_regular_season_totals', 'source': 'KBO official website',
        'official_snapshot_fetched_at': snapshot['fetched_at'], 'team_count': len(official_teams),
        'player_count': len(official_players), 'batting_players': len(tables['player_batting1']),
        'pitching_players': len(tables['player_pitching1']),
        'team_corrected_field_count': len(team_differences), 'team_matching_field_count': matched_fields,
        'provider_player_team_records': len(existing_players), 'identity_candidate_counts': dict(Counter(c['status'] for c in candidates)),
        'candidate_player_difference_count': len(player_differences),
        'all_provider_records_corrected': False,
        'rules': {
            'official_player_identity': 'Official batting/pitching/fielding/running tables joined by KBO player ID, not name.',
            'provider_crosswalk': 'Name/team candidates are unverified and never overwrite provider IDs or per-game rows.',
            'team_identity': 'Explicit KBO team abbreviation to existing full team name and ID mapping.',
            'transfer_scope': 'Official player totals are season-wide. Do not assign them to individual provider team stints.',
            'raw_games': 'Original game JSON is preserved. Season totals cannot locate or repair individual game errors.',
            'missing_game': 'Official season totals include games missing from provider statistics; that game is not marked repaired.',
            'omitted_stats': 'Absent official category is null, not zero; player fielding games are per-position, not additive appearances.',
            'field_semantics': 'Batting strikeouts and pitcher strikeouts are separate fields. No conversion of ambiguous provider strikeouts.',
        },
    }
    write_json(folder / 'aggregated/corrected_team_season_stats.json', {'metadata': metadata, 'teams': list(official_teams.values())})
    write_json(folder / 'aggregated/corrected_player_season_stats.json', {'metadata': metadata, 'players': list(official_players.values())})
    write_json(root / 'player_id_candidates.json', {'metadata': metadata, 'candidates': candidates})
    report = {'metadata': metadata, 'team_corrections': team_differences,
              'candidate_player_differences': player_differences, 'sources': snapshot['sources'],
              'remaining_work': ['Confirm cross-provider player IDs using independent identity evidence.',
                                 'Compare official per-game boxscores before editing individual game JSON.',
                                 'Team batting BB and SO are not exposed in the downloaded team batting page; not verified.']}
    write_json(root / 'reconciliation_report.json', report)
    return report


def grid(value, part='rows'):
    data = json.loads(value) if isinstance(value, str) else value
    rows = []
    for r in data.get(part, []):
        cells = []
        for c in r['row']:
            text = re.sub('<[^>]+>', '', c.get('Text') or '').replace('&nbsp;', '').strip()
            cells.append(text)
            cells.extend([''] * (int(c.get('ColSpan') or 1) - 1))
        rows.append(cells)
    return rows


def normalize_box(box, game, provider_id):
    if str(box.get('code')) != '100' or len(box.get('arrHitter', [])) != 2 or len(box.get('arrPitcher', [])) != 2:
        raise ValueError('공식 박스스코어 응답에 두 팀 기록이 없습니다.')
    teams = []
    for i, side in enumerate(('away', 'home')):
        hitters = box['arrHitter'][i]
        names, lines, results = grid(hitters['table1']), grid(hitters['table3']), grid(hitters['table2'])
        if not len(names) == len(lines) == len(results):
            raise ValueError('공식 타자 이름/기록/타석 행 수 불일치')
        batting = []
        for n, row, outcomes in zip(names, lines, results):
            if len(n) != 3 or len(row) != 5:
                raise ValueError('공식 타자 열 수 불일치')
            batting.append({'player_name': n[2], 'source_order': n[0], 'source_position': n[1],
                            'at_bats': number(row[0]), 'hits': number(row[1]),
                            'runs_batted_in': number(row[2]), 'runs': number(row[3]),
                            'plate_appearance_results_by_inning': outcomes})
        pitching = []
        for row in grid(box['arrPitcher'][i]['table']):
            if len(row) != 17:
                raise ValueError('공식 투수 열 수 불일치')
            pitching.append({'player_name': row[0], 'entry': row[1], 'result': row[2],
                             'outs_pitched': official_outs(row[6]), 'batters_faced': number(row[7]),
                             'pitches': number(row[8]), 'opponent_at_bats': number(row[9]),
                             'hits_allowed': number(row[10]), 'home_runs_allowed': number(row[11]),
                             'walks_and_hit_batters': number(row[12]), 'pitcher_strikeouts': number(row[13]),
                             'runs_allowed': number(row[14]), 'earned_runs': number(row[15])})
        totals = grid(hitters['table3'], 'tfoot')
        if len(totals) != 1 or len(totals[0]) != 5:
            raise ValueError('공식 타자 팀 합계 형식 불일치')
        team_batting = {f: number(totals[0][j]) for j, f in enumerate(('at_bats', 'hits', 'runs_batted_in', 'runs'))}
        for field, total in team_batting.items():
            if total is None or total != sum(p[field] for p in batting):
                raise ValueError(f'공식 박스스코어 타자 합계 불일치: {field}')
        team_pitching = {f: sum(p[f] for p in pitching) for f in
                         ('outs_pitched', 'batters_faced', 'pitches', 'hits_allowed', 'home_runs_allowed',
                          'walks_and_hit_batters', 'pitcher_strikeouts', 'runs_allowed', 'earned_runs')}
        # Individual pitcher ER can sum to a different value from official team ER.
        team_pitching['pitcher_earned_runs_sum'] = team_pitching.pop('earned_runs')
        score = int(game['T_SCORE_CN' if side == 'away' else 'B_SCORE_CN'])
        if team_batting['runs'] != score:
            raise ValueError('공식 경기 목록 점수와 박스스코어 득점이 다릅니다.')
        teams.append({'qualifier': side, 'official_team_name': game['AWAY_NM' if side == 'away' else 'HOME_NM'],
                      'runs_scored': score, 'batting': team_batting, 'pitching': team_pitching,
                      'batters': batting, 'pitchers': pitching})
    if any(teams[i]['runs_scored'] != teams[1-i]['pitching']['runs_allowed'] for i in range(2)):
        raise ValueError('공식 박스스코어 양 팀 득실점 불일치')
    return {'provider_event_id': provider_id, 'kbo_game_id': game['G_ID'], 'date': game['G_DT'],
            'source_url': BASE + '/Schedule/GameCenter/Main.aspx?gameDate=' + game['G_DT'] + '&gameId=' + game['G_ID'] + '&section=REVIEW',
            'player_identity': 'Official game rows contain names, not KBO player IDs; no forced cross-provider join.',
            'teams': teams}


def reconcile_games(folder, offline=False):
    root = folder / 'official'
    client = OfficialClient(root / 'raw')
    if not offline:
        client.get(BASE + '/Schedule/GameCenter/Main.aspx', 'game_center_session')
    provider_teams = json.loads((folder / 'teams.json').read_text(encoding='utf-8'))['competitors']
    short_names = {t['id']: next(k for k, v in TEAM_NAMES.items() if v == t['name']) for t in provider_teams}
    raws = sorted(folder.glob('sr_sport_event_*/game_raw.json'))
    corrected, differences, failures = [], [], []
    def process(path):
        raw = json.loads(path.read_text(encoding='utf-8'))
        event = raw['sport_event']
        eid = event['id']
        date = datetime.fromisoformat(event['start_time']).astimezone(timezone(timedelta(hours=9))).strftime('%Y%m%d')
        try:
            daily_path = root / f'raw/daily/{date}.json'
            if offline and not daily_path.exists():
                raise ValueError('공식 경기 목록 미확보')
            daily = client.public_json('/ws/Main.asmx/GetKboGameList', {'leId': '1', 'srId': '0', 'date': date}, daily_path)
            sides = {t['qualifier']: short_names[t['id']] for t in event['competitors']}
            matches = [g for g in daily['game'] if g['AWAY_NM'] == sides['away'] and g['HOME_NM'] == sides['home']
                       and str(g['SR_ID']) == '0' and g['G_DT'] == date and str(g['GAME_STATE_SC']) == '3'
                       and str(g.get('CANCEL_SC_ID')) == '0']
            if len(matches) > 1:
                start = datetime.fromisoformat(event['start_time']).astimezone(timezone(timedelta(hours=9))).strftime('%H:%M')
                matches = [g for g in matches if g['G_TM'] == start]
            if len(matches) != 1:
                raise ValueError(f'공식 경기 ID를 하나로 식별하지 못했습니다: {len(matches)}개')
            game = matches[0]
            game_path = root / f"raw/boxscores/{game['G_ID']}.json"
            if offline and not game_path.exists():
                raise ValueError('공식 박스스코어 미확보')
            box = client.public_json('/ws/Schedule.asmx/GetBoxScoreScroll',
                                     {'leId': '1', 'srId': '0', 'seasonId': str(game['SEASON_ID']), 'gameId': game['G_ID']}, game_path)
            data = normalize_box(box, game, eid)
            write_json(root / 'games' / (eid.replace(':', '_') + '.json'), data)
            corrected.append({'provider_event_id': eid, 'kbo_game_id': game['G_ID'], 'source_url': data['source_url']})
            old_teams = {t['id']: t for t in raw.get('statistics', {}).get('totals', {}).get('competitors', [])}
            for team in data['teams']:
                tid = next(t['id'] for t in event['competitors'] if t['qualifier'] == team['qualifier'])
                old = old_teams.get(tid, {}).get('statistics', {})
                for group, fields in [('batting', ('at_bats', 'hits', 'runs_batted_in', 'runs')),
                                      ('pitching', ('hits_allowed',))]:
                    for f in fields:
                        new = team[group][f]
                        if old.get(f) != new:
                            differences.append({'event_id': eid, 'team_id': tid, 'field': f'{group}.{f}',
                                                 'before': old.get(f), 'after': new, 'official_game_id': game['G_ID']})
        except (ValueError, KeyError, TypeError, OSError) as exc:
            failures.append({'event_id': eid, 'error': str(exc)})
    with ThreadPoolExecutor(max_workers=4) as pool:
        for i, _ in enumerate(pool.map(process, raws), 1):
            if i % 60 == 0 or i == len(raws):
                report = {'target_games': len(raws), 'verified_official_games': len(corrected),
                          'all_complete': len(corrected) == len(raws), 'team_game_corrections': list(differences),
                          'failures': list(failures), 'games': list(corrected)}
                write_json(root / 'game_reconciliation_report.json', report)
                print(f'공식 경기 대조 {i}/{len(raws)}: 성공 {len(corrected)}, 실패 {len(failures)}', flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description='KBO 공식 정규시즌 기록 확보·대조')
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parent.parent / 'kbo_data/kbo_2026_138278')
    parser.add_argument('--offline', action='store_true', help='저장된 공식 자료로 대조만 다시 실행')
    parser.add_argument('--games-only', action='store_true', help='시즌 표를 재수집하지 않고 공식 경기별 기록을 대조')
    args = parser.parse_args()
    source = json.loads((args.input / 'teams.json').read_text(encoding='utf-8'))
    root = args.input / 'official'
    snapshot = (json.loads((root / 'official_tables.json').read_text(encoding='utf-8')) if args.offline or args.games_only
                else download(root, int(source['season']['year'])))
    report = reconcile(args.input, snapshot)
    print(json.dumps(report['metadata'], ensure_ascii=False, indent=2))
    if args.games_only or not args.offline:
        games = reconcile_games(args.input, args.offline)
        print('공식 경기 검증 완료:', games['verified_official_games'], '/', games['target_games'])


if __name__ == '__main__':
    main()
