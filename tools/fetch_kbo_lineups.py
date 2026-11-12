"""Fetch positions and season lineups; join only on provider IDs, never names."""
import argparse
import getpass
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

if __package__:
    from .fetch_kbo import APIError, Client, regular_closed, write_json
else:  # Also support python tools/fetch_kbo_lineups.py
    from fetch_kbo import APIError, Client, regular_closed, write_json

POSITIONS = {'C', 'OF', 'P', 'IF', 'RP', 'DH', '2B', '1B', 'SP', 'LF', '3B',
             'CF', 'RF', 'SS', 'P-OF', 'P-DH', 'U'}
PITCHERS = {'P', 'SP', 'RP', 'P-OF', 'P-DH'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def cached(path):
    try:
        return read(path)
    except (OSError, ValueError):
        return None


def valid_id(value, kind):
    return isinstance(value, str) and re.fullmatch(r'sr:' + kind + r':\d+', value) is not None


def valid_team_profile(data, tid):
    if not isinstance(data, dict) or not isinstance(data.get('competitor'), dict):
        return False
    if data['competitor'].get('id') != tid or not isinstance(data.get('players'), list) or not data['players']:
        return False
    ids = [p.get('id') if isinstance(p, dict) else None for p in data['players']]
    return all(valid_id(pid, 'player') for pid in ids) and len(ids) == len(set(ids))


def valid_player_profile(data, pid):
    return (isinstance(data, dict) and isinstance(data.get('player'), dict)
            and data['player'].get('id') == pid and data['player'].get('type') in POSITIONS)


def local_inputs(folder):
    source = read(folder / 'teams.json')
    teams = {t['id']: t for t in source['competitors']}
    if len(teams) != len(source['competitors']) or not all(valid_id(t, 'competitor') for t in teams):
        raise ValueError('기존 팀 목록 ID가 유효하지 않거나 중복됩니다.')
    events = {}
    files = sorted((folder / 'raw').glob('summaries_*.json'))
    for index, path in enumerate(files):
        if path.name != f'summaries_{index:03d}.json':
            raise ValueError('기존 경기 목록 페이지가 누락됐습니다.')
        batch = read(path)['summaries']
        if len(batch) > 200 or (index < len(files) - 1 and len(batch) != 200):
            raise ValueError('기존 경기 목록 페이지 길이가 잘못됐습니다.')
        for summary in batch:
            if not regular_closed(summary):
                continue
            event = summary['sport_event']
            eid = event['id']
            if not valid_id(eid, 'sport_event') or event['sport_event_context']['season']['id'] != source['season']['id']:
                raise ValueError('기존 경기 목록 ID 또는 시즌 불일치')
            if eid in events and events[eid] != event:
                raise ValueError(f'기존 경기 목록 중복 충돌: {eid}')
            sides = {t['id']: t.get('qualifier') for t in event['competitors']}
            if len(sides) != 2 or set(sides.values()) != {'home', 'away'} or not set(sides) <= set(teams):
                raise ValueError(f'기존 경기 팀 식별 실패: {eid}')
            events[eid] = event
    if not files or len(read(files[-1])['summaries']) >= 200 or not events:
        raise ValueError('기존 종료 경기 전체 목록을 먼저 수집하세요.')
    stats_index = {}
    player_ids = set()
    for eid in events:
        raw = read(folder / eid.replace(':', '_') / 'game_raw.json')
        if raw.get('sport_event', {}).get('id') != eid:
            raise ValueError(f'기존 원본 경기 ID 불일치: {eid}')
        raw_event = raw['sport_event']
        expected = events[eid]
        if (raw_event.get('sport_event_context', {}).get('season', {}).get('id') != source['season']['id']
                or raw_event.get('start_time') != expected.get('start_time')
                or {t['id']: t.get('qualifier') for t in raw_event.get('competitors', [])}
                != {t['id']: t.get('qualifier') for t in expected['competitors']}):
            raise ValueError(f'기존 경기 목록과 원본의 시즌/시간/팀 불일치: {eid}')
        index = {}
        for team in raw.get('statistics', {}).get('totals', {}).get('competitors', []):
            ids = {p['id'] for p in team.get('players', [])}
            if not all(valid_id(pid, 'player') for pid in ids):
                raise ValueError(f'기존 선수 ID가 잘못됐습니다: {eid}')
            index[team['id']] = ids
            player_ids.update(ids)
        stats_index[eid] = index
    return source, events, stats_index, player_ids


def validate_lineup(data, expected, stats_index):
    try:
        return _validate_lineup(data, expected, stats_index)
    except (AttributeError, TypeError, KeyError, ValueError):
        return {'valid': False, 'errors': ['invalid_lineup_schema'], 'warnings': [], 'teams': []}


def _validate_lineup(data, expected, stats_index):
    """Structural validation is separate from statistical coverage warnings."""
    errors, warnings, normalized = [], [], []
    if not isinstance(data, dict):
        return {'valid': False, 'errors': ['lineup_absent'], 'warnings': [], 'teams': []}
    event = data.get('sport_event', {})
    if event.get('id') != expected['id']:
        errors.append('event_id_mismatch')
    actual_season = event.get('sport_event_context', {}).get('season', {}).get('id')
    expected_season = expected['sport_event_context']['season']['id']
    if actual_season is not None and actual_season != expected_season:
        errors.append('season_id_mismatch')
    if event.get('start_time') != expected.get('start_time'):
        errors.append('start_time_mismatch')
    expected_sides = {t['id']: t['qualifier'] for t in expected['competitors']}
    event_teams = event.get('competitors', [])
    if len(event_teams) != 2 or {t.get('id'): t.get('qualifier') for t in event_teams} != expected_sides:
        errors.append('event_teams_mismatch')
    lineups = data.get('lineups', {}).get('competitors', [])
    if len(lineups) != 2 or {t.get('id'): t.get('qualifier') for t in lineups} != expected_sides:
        errors.append('lineup_teams_mismatch')
    all_ids = set()
    for team in lineups:
        tid = team.get('id')
        rows = team.get('players', [])
        ids = [p.get('id') for p in rows]
        team_errors = []
        if not rows:
            team_errors.append('players_absent')
        if any(not valid_id(pid, 'player') for pid in ids):
            team_errors.append('invalid_player_id')
        if len(set(ids)) != len(ids):
            team_errors.append('duplicate_player_id')
        if all_ids.intersection(ids):
            team_errors.append('player_on_both_teams')
        all_ids.update(ids)
        if any('starter' in p and type(p['starter']) is not bool for p in rows):
            team_errors.append('invalid_starter_type')
        if any(p.get('order') is not None and (type(p['order']) is not int or not 1 <= p['order'] <= 9) for p in rows):
            team_errors.append('invalid_batting_order')
        batters = [p for p in rows if p.get('starter') is True and p.get('order') is not None]
        if len(batters) != 9 or Counter(p.get('order') for p in batters) != Counter(range(1, 10)):
            team_errors.append('starting_batting_order_not_1_to_9')
        pitchers = [p for p in rows if p.get('starter') is True and p.get('type') in PITCHERS]
        if len(pitchers) != 1:
            team_errors.append('starting_pitcher_not_unique')
        if any(p.get('starter') is True and p.get('order') is None and p not in pitchers for p in rows):
            team_errors.append('unexplained_starter_without_order')
        if any(p.get('starter') is True and p.get('type') not in POSITIONS for p in rows):
            team_errors.append('starter_position_absent_or_unknown')
        stat_ids = stats_index.get(tid)
        if stat_ids is None or not stat_ids:
            warnings.append({'team_id': tid, 'code': 'existing_player_statistics_absent'})
        else:
            absent = sorted(set(ids) - stat_ids, key=str)
            if absent:
                warnings.append({'team_id': tid, 'code': 'lineup_players_without_stat_rows', 'player_ids': absent})
            other_ids = set().union(*(v for k, v in stats_index.items() if k != tid))
            if (set(ids) - stat_ids) & other_ids:
                team_errors.append('player_matches_opposing_team_statistics')
        errors.extend(f'{tid}:{code}' for code in team_errors)
        normalized.append({
            'team_id': tid, 'qualifier': team.get('qualifier'),
            'starting_batters': [{'player_id': p.get('id'), 'order': p.get('order'),
                                 'source_position': p.get('type')} for p in
                                sorted(batters, key=lambda p: p['order'] if type(p['order']) is int else 99)],
            'starting_pitcher_id': pitchers[0]['id'] if len(pitchers) == 1 else None,
            'players': [{'player_id': p.get('id'), 'player_name': p.get('name'),
                         'source_position': p.get('type'), 'starter': p.get('starter'),
                         'order': p.get('order')} for p in rows],
        })
    return {'valid': not errors, 'errors': errors, 'warnings': warnings, 'teams': normalized}


def request(client, path, destination, failures, **params):
    try:
        data = client.get(path, **params)
        write_json(destination, data)
        return data
    except RuntimeError as exc:
        failures.append({'path': path, 'error': str(exc)})
        if isinstance(exc, APIError) and exc.status in (401, 403, 429):
            raise
        return None


def collect(client, folder, refresh=False, max_games=0):
    source, events, stats_index, existing_players = local_inputs(folder)
    out = folder / 'supplemental'
    results, profiles, failures = {}, {}, []
    seen_events, conflicting_events = set(), set()
    seen_rows = {}
    page_complete = False
    status = 'collecting'
    write_json(out / 'collection_status.json', {'status': status, 'all_complete': False})
    try:
        # Retain valid per-game files first; failed pagination cannot erase prior work.
        if not refresh:
            for eid, expected in events.items():
                data = cached(out / 'raw/games' / (eid.replace(':', '_') + '.json'))
                if data is not None and validate_lineup(data, expected, stats_index[eid])['valid']:
                    results[eid] = data
        cached_events = set(results)
        signatures = set()
        for page in range(100):
            path = out / f'raw/season_lineups_{page:03d}.json'
            data = None if refresh else cached(path)
            if not isinstance(data, dict) or not isinstance(data.get('lineups'), list):
                data = request(client, f"seasons/{source['season']['id']}/lineups", path,
                               failures, start=page * 100, limit=100)
            if data is None:
                break
            batch = data.get('lineups')
            if not isinstance(batch, list) or len(batch) > 100:
                failures.append({'code': 'invalid_season_lineups_schema', 'page': page, 'keys': list(data)})
                break
            signature = json.dumps(batch, sort_keys=True)
            if batch and signature in signatures:
                failures.append({'code': 'repeated_season_lineups_page', 'page': page})
                break
            signatures.add(signature)
            for row in batch:
                eid = row.get('sport_event', {}).get('id')
                if not valid_id(eid, 'sport_event'):
                    failures.append({'code': 'invalid_season_lineup_event_id', 'page': page})
                    continue
                if eid not in events:
                    continue  # Cancelled/postponed/playoff games are outside our target.
                if eid in seen_rows and seen_rows[eid] != row:
                    conflicting_events.add(eid)
                seen_rows[eid] = row
                seen_events.add(eid)
                # A cached game response takes precedence over an invalid season row.
                if eid not in cached_events and (eid not in results or validate_lineup(row, events[eid], stats_index[eid])['valid']):
                    results[eid] = row
                if validate_lineup(results[eid], events[eid], stats_index[eid])['valid'] and eid not in conflicting_events:
                    write_json(out / 'raw/games' / (eid.replace(':', '_') + '.json'), results[eid])
            print(f'시즌 라인업 {page + 1}페이지: {len(batch)}경기 / 대상 매칭 {len(seen_events)}')
            if len(batch) < 100:
                page_complete = True
                break
        # Resolve missing, conflicting, or invalid season rows via an individual request.
        attempted = 0
        for eid, expected in events.items():
            valid = validate_lineup(results.get(eid), expected, stats_index[eid])['valid']
            if valid and eid not in conflicting_events:
                continue
            if max_games and attempted >= max_games:
                break
            attempted += 1
            data = request(client, f'sport_events/{eid}/lineups',
                           out / 'raw/games' / (eid.replace(':', '_') + '.json'), failures)
            if data is not None:
                results[eid] = data
                conflicting_events.discard(eid)
            print(f'경기별 보완 {attempted}: {eid}')
        # Current squad is a dated profile snapshot, not historical team membership.
        for team in source['competitors']:
            tid = team['id']
            path = out / 'raw/team_profiles' / (tid.replace(':', '_') + '.json')
            data = None if refresh else cached(path)
            if not valid_team_profile(data, tid):
                data = request(client, f'competitors/{tid}/profile', path, failures)
            if valid_team_profile(data, tid):
                profiles[tid] = data
            else:
                failures.append({'code': 'team_profile_missing_or_id_mismatch', 'team_id': tid})
        known_positions = set()
        for data in profiles.values():
            known_positions.update(p.get('id') for p in data.get('players', []) if p.get('type') in POSITIONS)
        for eid, data in results.items():
            if eid in conflicting_events or not validate_lineup(data, events[eid], stats_index[eid])['valid']:
                continue
            for team in data['lineups']['competitors']:
                known_positions.update(p.get('id') for p in team.get('players', []) if p.get('type') in POSITIONS)
        for pid in sorted(existing_players - known_positions):
            path = out / 'raw/player_profiles' / (pid.replace(':', '_') + '.json')
            data = None if refresh else cached(path)
            if not valid_player_profile(data, pid):
                request(client, f'players/{pid}/profile', path, failures)
        status = 'finished'
    except (KeyboardInterrupt, EOFError):
        status = 'interrupted'
        raise
    except Exception:
        status = 'failed'
        raise
    finally:
        report = publish(out, source, events, stats_index, existing_players, results,
                         profiles, failures, page_complete, conflicting_events, status)
        print(f"라인업 검증 {report['valid_lineup_games']}/{len(events)} / 선수 포지션 {report['existing_players_with_position']}/{len(existing_players)}")
        print(f'현황: {out / "collection_status.json"}')
    return report


def publish(out, source, events, stats_index, existing_players, results, profiles,
            failures, page_complete, conflicting_events, status):
    games, evidence = [], {}

    def position(pid, code, **origin):
        if valid_id(pid, 'player'):
            evidence.setdefault(pid, []).append(dict(position=code if code in POSITIONS else None,
                                                     source_position=code, **origin))

    for eid, expected in events.items():
        data = results.get(eid)
        checked = validate_lineup(data, expected, stats_index[eid])
        if eid in conflicting_events:
            checked['valid'] = False
            checked['errors'].append('conflicting_duplicate_season_lineups')
        games.append({'event_id': eid, 'start_time': expected['start_time'],
                      'matched_existing_game': True, **checked})
        if checked['valid']:
            for team in checked['teams']:
                for p in team['players']:
                    position(p['player_id'], p['source_position'], source='game_lineup',
                             event_id=eid, team_id=team['team_id'])
    for tid, data in profiles.items():
        for p in data.get('players', []):
            position(p.get('id'), p.get('type'), source='current_team_profile', team_id=tid,
                     generated_at=data.get('generated_at'))
    for pid in existing_players:
        data = cached(out / 'raw/player_profiles' / (pid.replace(':', '_') + '.json'))
        if valid_player_profile(data, pid):
            position(pid, data['player'].get('type'), source='current_player_profile',
                     generated_at=data.get('generated_at'))
    player_rows = []
    for pid in sorted(existing_players | set(evidence)):
        observations = evidence.get(pid, [])
        codes = sorted({p['position'] for p in observations if p['position'] is not None})
        player_rows.append({'player_id': pid, 'has_existing_statistics': pid in existing_players,
                            'positions_observed': codes, 'position_available': bool(codes),
                            'multiple_position_codes': len(codes) > 1, 'observations': observations})
    missing_positions = [p['player_id'] for p in player_rows
                         if p['has_existing_statistics'] and not p['position_available']]
    valid_games = sum(g['valid'] for g in games)
    report = {
        'updated_at': datetime.now(timezone.utc).isoformat(), 'status': status,
        'season': source['season'], 'target_scope': 'existing_closed_regular_season_games',
        'target_games': len(events), 'valid_lineup_games': valid_games,
        'invalid_or_missing_game_ids': [g['event_id'] for g in games if not g['valid']],
        'season_pages_complete': page_complete, 'team_profiles_received': len(profiles),
        'existing_players': len(existing_players),
        'existing_players_with_position': len(existing_players) - len(missing_positions),
        'existing_player_ids_without_position': missing_positions,
        'all_complete': (status == 'finished' and valid_games == len(events) and not missing_positions
                         and len(profiles) == len(source['competitors'])),
        'request_or_schema_failures': failures,
        'rules': {
            'identity': 'Join only by season/event/team/player IDs; never by display name.',
            'batting_order': 'Exactly nine starter=true batters at unique slots 1..9; substitute slots may repeat.',
            'pitcher': 'Exactly one starter=true player with a pitcher position code.',
            'positions': 'Provider position classifications, often broad IF/OF; not a guarantee of actual defensive spot.',
            'profiles': 'Current snapshots; never use current team to rewrite a historical game team.',
            'validation': 'Valid means structural checks passed, not independent confirmation against official scorecards.',
            'existing_statistics': 'Missing stat rows are warnings unless a player matches the opposing team; lineups cannot fill missing statistics.',
            'completion': 'All target games validated and all existing player IDs have position evidence; season pagination may be supplemented by individual game requests.',
        },
    }
    write_json(out / 'season_lineups.json', {'metadata': report, 'games': games})
    write_json(out / 'player_positions.json', {'metadata': report, 'players': player_rows})
    write_json(out / 'collection_status.json', report)
    return report


def main():
    parser = argparse.ArgumentParser(description='기존 KBO 데이터와 ID를 대조하며 포지션·시즌 라인업 수집')
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parent.parent / 'kbo_data/kbo_2026_138278')
    parser.add_argument('--refresh', action='store_true', help='저장된 API 응답도 다시 조회')
    parser.add_argument('--max-games', type=int, default=0, help='경기별 보완 호출 상한 (0: 전체); 시즌 목록·프로필 조회는 별도')
    args = parser.parse_args()
    if args.max_games < 0:
        parser.error('--max-games는 0 이상이어야 합니다.')
    key = os.environ.get('SPORTRADAR_API_KEY', '').strip()
    if not key:
        key = getpass.getpass('Sportradar API 키 (화면에 표시되지 않음): ').strip()
    if not key:
        parser.exit(1, 'API 키가 비어 있습니다.\n')
    try:
        report = collect(Client(key), args.input.resolve(), args.refresh, args.max_games)
        return 0 if report['all_complete'] else 2
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        print(f'수집 중단: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        sys.exit('\n중단했습니다. 저장된 응답은 다음 실행에서 재사용합니다.')
