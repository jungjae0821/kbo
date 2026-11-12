"""Resolve provider IDs with corroborating official games or biographical evidence."""
import argparse
import getpass
import hashlib
import json
import os
import re
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import parse_qs, urlparse

if __package__:
    from .aggregate_kbo import innings_to_outs
else:  # Also support python tools/resolve_player_ids.py
    from aggregate_kbo import innings_to_outs
if __package__:
    from .fetch_kbo import APIError, Client, write_json
else:  # Also support python tools/resolve_player_ids.py
    from fetch_kbo import APIError, Client, write_json
if __package__:
    from .reconcile_kbo import BASE, OfficialClient, Page, TEAM_NAMES
else:  # Also support python tools/resolve_player_ids.py
    from reconcile_kbo import BASE, OfficialClient, Page, TEAM_NAMES


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def aliases(name):
    compact = re.sub(r'[,\s]', '', name or '')
    result = {compact} if compact else set()
    if re.fullmatch('[가-힣]{3}', compact):
        result.add(compact[-1] + compact[:-1])
    if ',' in (name or ''):
        result.update(p.strip() for p in name.split(',') if len(p.strip()) >= 2)
    return result


def game_evidence(folder):
    official = read(folder / 'aggregated/corrected_player_season_stats.json')['players']
    index = defaultdict(set)
    for p in official:
        for team in p['official_team_names']:
            index[(p['player_name'], team)].add(p['kbo_player_id'])
    evidence = defaultdict(lambda: defaultdict(list))
    providers = defaultdict(lambda: {'names': set(), 'teams': set()})
    for path in sorted(folder.glob('sr_sport_event_*/game_raw.json')):
        raw = read(path)
        game = read(folder / 'official/games' / (path.parent.name + '.json'))
        for team in raw.get('statistics', {}).get('totals', {}).get('competitors', []):
            short = next(k for k, v in TEAM_NAMES.items() if v == team['name'])
            canonical = next(t for t in game['teams'] if t['official_team_name'] == short)
            for row in team.get('players', []):
                pid = row['id']
                providers[pid]['names'].add(row.get('name', ''))
                providers[pid]['teams'].add(short)
                names = aliases(row.get('name'))
                stats = dict(row.get('statistics', {}))
                stats['outs_pitched'] = innings_to_outs(stats.get('innings_pitched'))
                for role, fields, minimum in [
                    ('batters', ('at_bats', 'hits', 'runs_batted_in', 'runs'), 'at_bats'),
                    ('pitchers', ('outs_pitched', 'hits_allowed', 'earned_runs'), 'outs_pitched'),
                ]:
                    for player in canonical[role]:
                        if player['player_name'] not in names or player[minimum] < (2 if role == 'batters' else 3):
                            continue
                        ids = index[(player['player_name'], short)]
                        # A same-name player with more than one official ID needs bio evidence.
                        if len(ids) != 1 or not all(stats.get(f) == player[f] for f in fields):
                            continue
                        kid = next(iter(ids))
                        evidence[pid][kid].append({'provider_event_id': raw['sport_event']['id'],
                                                  'kbo_game_id': game['kbo_game_id'],
                                                  'official_name': player['player_name'], 'team': short,
                                                  'role': role, 'matching_fields': {f: player[f] for f in fields}})
    return official, providers, evidence


def bio_from_html(html, kid):
    def text(suffix):
        m = re.search(r'<span[^>]+id="[^"]*' + suffix + r'"[^>]*>(.*?)</span>', html, re.S)
        return re.sub('<[^>]+>', '', m[1]).strip() if m else None
    birthday = text('lblBirthday')
    m = re.fullmatch(r'(\d{4})년\s*(\d{2})월\s*(\d{2})일', birthday or '')
    height = re.search(r'(\d+)cm', text('lblHeightWeight') or '')
    return {'kbo_player_id': kid, 'name': text('lblName'),
            'date_of_birth': '-'.join(m.groups()) if m else None,
            'height': int(height[1]) if height else None,
            'source': f'{BASE}/Record/Player/HitterDetail/Basic.aspx?playerId={kid}'}


def choose_bio(profile, official_bios, provider, corroboration):
    """DOB alone never resolves identity: require compatible name or height + games."""
    player = profile.get('player', {})
    dob = player.get('date_of_birth')
    if not dob:
        return None, 'provider_birth_date_absent'
    names = set().union(*(aliases(n) for n in provider['names']), aliases(player.get('name')))
    candidates = []
    for bio in official_bios:
        if bio.get('date_of_birth') != dob:
            continue
        name_matches = bio.get('name') in names
        height_matches = player.get('height') is not None and player.get('height') == bio.get('height')
        games_match = bool(corroboration.get(bio['kbo_player_id']))
        if name_matches or (height_matches and games_match):
            candidates.append((bio, name_matches, height_matches))
    if len(candidates) != 1:
        return None, 'bio_candidates_ambiguous' if candidates else 'bio_identity_not_confirmed'
    return candidates[0], None


def search_bios_from_pages(paths):
    result = {}
    for path in paths:
        page = Page(path.read_text(encoding='utf-8-sig'))
        for table in page.tables:
            if table['attrs'].get('class') != 'tEx':
                continue
            for cells in table['rows'][1:]:
                links = [link for cell in cells for link in cell['links'] if 'playerId=' in link]
                if not links or len(cells) != 7:
                    continue
                kid = parse_qs(urlparse(links[0]).query)['playerId'][0]
                texts = [cell['text'] for cell in cells]
                height = re.search(r'(\d+)cm', texts[5])
                bio = {'kbo_player_id': kid, 'name': texts[1], 'date_of_birth': texts[4],
                       'height': int(height[1]) if height else None, 'source': BASE + links[0]}
                if kid in result and result[kid]['date_of_birth'] != bio['date_of_birth']:
                    raise ValueError(f'공식 검색 생년월일 충돌: {kid}')
                result[kid] = bio
    return result


def resolve(folder, official, providers, evidence):
    bio_dir = folder / 'official/identity'
    bios_by_id = {}
    for path in (bio_dir / 'kbo_profiles').glob('*.html'):
        bio = bio_from_html(path.read_text(encoding='utf-8-sig'), path.stem)
        if bio['name'] and bio['date_of_birth']:
            bios_by_id[bio['kbo_player_id']] = bio
    search_path = bio_dir / 'search_bios.json'
    # Index every saved page even if a later network request interrupted collection.
    saved_search = search_bios_from_pages((bio_dir / 'search').glob('*.html'))
    if saved_search:
        write_json(search_path, list(saved_search.values()))
    if search_path.exists():
        for bio in read(search_path):
            previous = bios_by_id.get(bio['kbo_player_id'])
            if previous and previous['date_of_birth'] != bio.get('date_of_birth'):
                raise ValueError(f"공식 생년월일 출처 충돌: {bio['kbo_player_id']}")
            bios_by_id.setdefault(bio['kbo_player_id'], bio)
    bios = list(bios_by_id.values())
    game_choices = {}
    for pid, options in evidence.items():
        candidates = [kid for kid, rows in options.items()
                      if len({r['provider_event_id'] for r in rows}) >= 3]
        if len(candidates) == 1:
            game_choices[pid] = candidates[0]
    reverse = Counter(game_choices.values())
    rows = []
    for pid, provider in sorted(providers.items()):
        item = {'provider_player_id': pid, 'provider_names': sorted(provider['names']),
                'observed_teams': sorted(provider['teams']), 'verified': False,
                'kbo_player_id': None, 'method': None, 'reason': 'insufficient_independent_evidence'}
        profile_path = bio_dir / 'provider_profiles' / (pid.replace(':', '_') + '.json')
        selection = None
        if profile_path.exists():
            profile = read(profile_path)
            if profile.get('player', {}).get('id') != pid:
                item['reason'] = 'provider_profile_id_mismatch'
            else:
                selection, reason = choose_bio(profile, bios, provider, evidence.get(pid, {}))
                item['reason'] = reason
        if selection:
            bio, name_match, height_match = selection
            item.update(verified=True, kbo_player_id=bio['kbo_player_id'], method='birth_date_and_name_or_height_plus_game',
                        evidence={'date_of_birth': bio['date_of_birth'], 'official_name': bio['name'],
                                  'name_matches': name_match, 'height_matches': height_match, 'source': bio['source']})
        elif not profile_path.exists() and pid in game_choices and reverse[game_choices[pid]] == 1:
            kid = game_choices[pid]
            item.update(verified=True, kbo_player_id=kid, method='unique_name_team_and_multiple_exact_game_records',
                        reason=None, evidence=evidence[pid][kid])
        elif pid in game_choices and reverse[game_choices[pid]] > 1:
            item['reason'] = 'multiple_provider_ids_share_official_candidate_requires_bio'
        item['game_candidate_ids'] = sorted(evidence.get(pid, {}))
        rows.append(item)
    verified = [r for r in rows if r['verified']]
    metadata = {'provider_player_ids': len(rows), 'verified_player_ids': len(verified),
                'unresolved_player_ids': len(rows) - len(verified), 'all_complete': len(rows) == len(verified),
                'method_counts': dict(Counter(r['method'] for r in verified)),
                'rule': 'No name-only merges. Multi-game links require a unique official name/team ID, at least three exact nontrivial game stat matches, and no competing provider ID. Bio links require exact DOB plus compatible name or matching height and game evidence.',
                'scope': 'Player identity only. Never move a season total into a historical team stint.'}
    write_json(bio_dir / 'player_id_crosswalk.json', {'metadata': metadata, 'players': rows})
    write_json(bio_dir / 'unresolved_player_ids.json', {'metadata': metadata, 'players': [r for r in rows if not r['verified']]})
    by_id = defaultdict(list)
    for item in verified:
        by_id[item['kbo_player_id']].append(item['provider_player_id'])
    enriched = []
    for p in official:
        enriched.append(dict(p, verified_provider_player_ids=sorted(by_id.get(p['kbo_player_id'], []))))
    write_json(folder / 'aggregated/linked_player_season_stats.json', {'metadata': metadata, 'players': enriched})
    return metadata, rows


def collect_profiles(folder, official, providers, rows, key, max_profiles):
    root = folder / 'official/identity'
    api = Client(key) if key else None
    failures = []
    requested = 0
    for row in rows:
        if api is None:
            break
        if row['verified']:
            continue
        pid = row['provider_player_id']
        path = root / 'provider_profiles' / (pid.replace(':', '_') + '.json')
        if path.exists():
            data = read(path)
            if data.get('player', {}).get('id') == pid and data['player'].get('date_of_birth'):
                continue
        if max_profiles and requested >= max_profiles:
            break
        requested += 1
        try:
            data = api.get(f'players/{pid}/profile')
            if data.get('player', {}).get('id') != pid:
                raise ValueError('프로필 응답 ID가 요청 ID와 다릅니다.')
            write_json(path, data)
        except (RuntimeError, ValueError, OSError) as exc:
            failures.append({'provider_player_id': pid, 'error': str(exc)})
            write_json(root / 'profile_collection_errors.json', failures)
            print(f'프로필 보류: {pid}: {exc}', flush=True)
            if isinstance(exc, APIError) and exc.status in (401, 403, 429):
                break  # Continue the independent, public KBO verification stage.
            continue
        print(f'선수 프로필 {requested}: {pid}', flush=True)

    # Official profile pages expose stable player ID + DOB. Cache these independently.
    def fetch_official(player):
        kid = player['kbo_player_id']
        destination = root / f'kbo_profiles/{kid}.html'
        if destination.exists() and bio_from_html(destination.read_text(encoding='utf-8-sig'), kid)['date_of_birth']:
            return
        c = OfficialClient(root / 'kbo_profiles')
        c.get(f'{BASE}/Record/Player/HitterDetail/Basic.aspx?playerId={kid}', kid)
    with ThreadPoolExecutor(max_workers=4) as pool:
        for i, _ in enumerate(pool.map(fetch_official, official), 1):
            if i % 100 == 0:
                print(f'공식 생년월일 {i}/{len(official)}', flush=True)

    # Include registered/retired players absent from this year's season stats.
    c = OfficialClient(root / 'search')
    from urllib.parse import urlencode
    names = set()
    for row in rows:
        if row['verified']:
            continue
        for name in row['provider_names']:
            names.update(n for n in aliases(name) if re.fullmatch('[가-힣]{2,4}', n))
    extra = {}
    def search(name):
        found = {}
        label = hashlib.sha256(name.encode()).hexdigest()[:16]
        path = root / 'search' / (label + '.html')
        if path.exists():
            page = Page(path.read_text(encoding='utf-8-sig'))
        else:
            try:
                page = c.get(BASE + '/Player/Search.aspx?' + urlencode({'searchWord': name}), label)
            except (OSError, ValueError) as exc:
                failures.append({'official_search': name, 'error': str(exc)})
                return found
        for table in page.tables:
            if table['attrs'].get('class') != 'tEx':
                continue
            for cells in table['rows'][1:]:
                links = [link for cell in cells for link in cell['links'] if 'playerId=' in link]
                if not links or len(cells) != 7:
                    continue
                kid = parse_qs(urlparse(links[0]).query)['playerId'][0]
                texts = [cell['text'] for cell in cells]
                height = re.search(r'(\d+)cm', texts[5])
                found[kid] = {'kbo_player_id': kid, 'name': texts[1], 'date_of_birth': texts[4],
                              'height': int(height[1]) if height else None, 'source': BASE + links[0]}
        return found
    with ThreadPoolExecutor(max_workers=4) as pool:
        for found in pool.map(search, sorted(names)):
            extra.update(found)
    write_json(root / 'search_bios.json', list(extra.values()))
    if failures:
        write_json(root / 'profile_collection_errors.json', failures)
    return extra


def main():
    parser = argparse.ArgumentParser(description='공식 경기·생년월일 근거로 Sportradar ↔ KBO 선수 ID 연결')
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parent.parent / 'kbo_data/kbo_2026_138278')
    parser.add_argument('--collect-profiles', action='store_true', help='보류 선수의 프로필을 API로 수집하여 생년월일 대조')
    parser.add_argument('--collect-official', action='store_true', help='API 키 없이 공식 프로필·검색 자료만 보완하여 재검증')
    parser.add_argument('--max-profiles', type=int, default=0, help='이번 실행의 Sportradar 프로필 호출 상한 (0: 전체)')
    args = parser.parse_args()
    if args.max_profiles < 0:
        parser.error('--max-profiles는 0 이상이어야 합니다.')
    official, providers, evidence = game_evidence(args.input)
    metadata, rows = resolve(args.input, official, providers, evidence)
    print('현재 ID 연결:', metadata, flush=True)
    if args.collect_profiles or args.collect_official:
        key = None
        if args.collect_profiles:
            key = os.environ.get('SPORTRADAR_API_KEY', '').strip() or getpass.getpass('Sportradar API 키 (화면에 표시되지 않음): ').strip()
            if not key:
                parser.exit(1, 'API 키가 비어 있습니다.\n')
        try:
            collect_profiles(args.input, official, providers, rows, key, args.max_profiles)
        finally:
            metadata, _ = resolve(args.input, official, providers, evidence)
            print('최종 ID 연결:', metadata, flush=True)
    return 0 if metadata['all_complete'] else 2


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, EOFError):
        raise SystemExit('중단했습니다. 같은 명령으로 이어받을 수 있습니다.')
