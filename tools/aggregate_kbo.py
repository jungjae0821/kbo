"""Aggregate saved regular-season JSON without network calls or source edits."""
import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path

if __package__:
    from .fetch_kbo import regular_closed, write_json
else:  # Also support python tools/aggregate_kbo.py
    from fetch_kbo import regular_closed, write_json


FIELDS = (
    'at_bats', 'earned_runs', 'errors', 'hits', 'hits_allowed', 'home_runs',
    'innings_pitched', 'runs', 'runs_batted_in', 'saves', 'stolen_bases',
    'strikeouts', 'walks', 'walks_allowed',
)
UNAVAILABLE = ['plate_appearances', 'doubles', 'triples', 'hit_by_pitch',
               'sacrifice_flies', 'batters_faced', 'home_runs_allowed',
               'pitcher_wins', 'pitcher_losses', 'pitcher_strikeouts']


def integer(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        number = Decimal(str(value))
        if number.is_finite() and number >= 0 and number == number.to_integral_value():
            return int(number)
    except InvalidOperation:
        pass
    return None


def innings_to_outs(value):
    """Baseball notation: 5.2 means five innings and two outs, not 5.2 innings."""
    if value is None or isinstance(value, bool):
        return None
    try:
        number = Decimal(str(value))
        if not number.is_finite() or number < 0:
            return None
        whole = int(number)
        fraction = (number - whole) * 10
        if fraction in (0, 1, 2):
            return whole * 3 + int(fraction)
    except InvalidOperation:
        pass
    return None


def accumulator():
    return {'sums': Counter(), 'counts': Counter(), 'records': 0}


def add_stats(acc, stats, issues, context):
    acc['records'] += 1
    for field in FIELDS:
        value = stats.get(field)
        parsed = innings_to_outs(value) if field == 'innings_pitched' else integer(value)
        if parsed is None:
            if value is not None:
                issues.append(dict(context, code='invalid_stat_value', field=field, value=value))
            continue
        acc['sums'][field] += parsed
        acc['counts'][field] += 1


def finish_stats(acc):
    totals = {f: acc['sums'][f] if acc['counts'][f] else None for f in FIELDS}
    outs = totals['innings_pitched']
    totals['outs_pitched'] = outs
    totals['innings_pitched'] = f'{outs // 3}.{outs % 3}' if outs is not None else None
    missing = {f: acc['records'] - acc['counts'][f] for f in FIELDS
               if acc['counts'][f] != acc['records'] or not acc['records']}
    return totals, missing


def rates(totals, partial_fields):
    def ratio(numerator, denominator, scale=1):
        if any(f in partial_fields for f in (numerator, denominator)):
            return None
        a, b = totals[numerator], totals[denominator]
        return round(scale * a / b, 6) if a is not None and b else None
    # Rates describe observed records only; coverage flags still apply.
    return {
        'batting_average': ratio('hits', 'at_bats'),
        'earned_run_average': (None if 'innings_pitched' in partial_fields else
                               ratio('earned_runs', 'outs_pitched', 27)),
        'on_base_percentage': None, 'slugging_percentage': None, 'ops': None,
    }


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def aggregate(folder):
    source = load(folder / 'teams.json')
    season = source['season']
    teams = {t['id']: dict(team_id=t['id'], team_name=t['name'], games=0,
                         wins=0, losses=0, ties=0, runs_scored=0, runs_allowed=0,
                         missing_score_game_ids=[], missing_player_stats_game_ids=[],
                         team_stats_game_ids=[], acc=accumulator())
             for t in source['competitors']}
    summaries = {}
    page_counts = []
    for index, path in enumerate(sorted((folder / 'raw').glob('summaries_*.json'))):
        if path.name != f'summaries_{index:03d}.json':
            raise ValueError('경기 목록 페이지 번호에 누락이 있습니다.')
        batch = load(path)['summaries']
        page_counts.append(len(batch))
        for row in batch:
            if regular_closed(row):
                eid = row['sport_event']['id']
                if eid in summaries and summaries[eid] != row:
                    raise ValueError(f'중복 경기 목록의 내용이 다릅니다: {eid}')
                summaries[eid] = row
    if not page_counts or page_counts[-1] >= 200 or any(n != 200 for n in page_counts[:-1]):
        raise ValueError('전체 경기 목록의 마지막 페이지까지 확보되지 않았습니다.')
    if not summaries:
        raise ValueError('집계할 종료된 정규시즌 경기가 없습니다.')

    players = {}
    missing_games = []
    issues = []
    raw_missing = []
    player_game_count = 0
    raw_count = 0
    for eid, summary in summaries.items():
        event_folder = folder / eid.replace(':', '_')
        try:
            raw = load(event_folder / 'game_raw.json')
            if raw.get('sport_event', {}).get('id') != eid or not regular_closed(raw):
                raise ValueError(f'경기 원본 ID 또는 상태 불일치: {eid}')
            raw_count += 1
        except FileNotFoundError:
            raw_missing.append(eid)
            raw = summary
        event = raw['sport_event']
        if event['sport_event_context']['season']['id'] != season['id']:
            raise ValueError(f'다른 시즌 원본: {eid}')
        sides = {t['qualifier']: t['id'] for t in event['competitors']}
        if set(sides) != {'home', 'away'} or len(set(sides.values())) != 2:
            raise ValueError(f'홈/원정 팀 식별 실패: {eid}')
        status = raw['sport_event_status']
        home_score, away_score = integer(status.get('home_score')), integer(status.get('away_score'))
        stat_teams = raw.get('statistics', {}).get('totals', {}).get('competitors', [])
        stat_ids = [t['id'] for t in stat_teams]
        if len(stat_ids) != len(set(stat_ids)) or not set(stat_ids) <= set(sides.values()):
            raise ValueError(f'중복 또는 다른 팀의 통계: {eid}')
        stats_by_team = {t['id']: t for t in stat_teams}
        game_missing_teams = []
        for side, tid in sides.items():
            team = teams[tid]
            team['games'] += 1
            scored, allowed = (home_score, away_score) if side == 'home' else (away_score, home_score)
            if scored is None or allowed is None:
                team['missing_score_game_ids'].append(eid)
            else:
                team['runs_scored'] += scored
                team['runs_allowed'] += allowed
                team['wins' if scored > allowed else 'losses' if scored < allowed else 'ties'] += 1
            team_data = stats_by_team.get(tid, {})
            team_stats = team_data.get('statistics', {})
            if team_stats:
                team['team_stats_game_ids'].append(eid)
                add_stats(team['acc'], team_stats, issues, {'event_id': eid, 'team_id': tid})
            records = [r for r in team_data.get('players', []) if r.get('statistics')]
            if not records:
                team['missing_player_stats_game_ids'].append(eid)
                game_missing_teams.append(tid)
                continue
            seen_records = set()
            field_totals = Counter()
            for row in records:
                pid = row.get('id')
                if not pid:
                    raise ValueError(f'선수 ID가 없습니다: {eid}')
                key = (pid, tid)
                role = row.get('type')
                duplicate_key = (pid, role)
                if duplicate_key in seen_records:
                    raise ValueError(f'경기 안에 중복 선수/역할 기록: {eid}, {pid}, {role}')
                seen_records.add(duplicate_key)
                player = players.setdefault(key, {
                    'player_id': pid, 'team_id': tid, 'names': set(), 'game_ids': set(),
                    'source_roles': Counter(), 'acc': accumulator(),
                    'non_pitcher_role_with_pitching_game_ids': set(),
                })
                player['names'].add(row.get('name') or pid)
                player['game_ids'].add(eid)
                player['source_roles'][str(role) if role is not None else 'unknown'] += 1
                context = {'event_id': eid, 'team_id': tid, 'player_id': pid}
                add_stats(player['acc'], row['statistics'], issues, context)
                outs = innings_to_outs(row['statistics'].get('innings_pitched'))
                if role != 'pitcher' and outs:
                    player['non_pitcher_role_with_pitching_game_ids'].add(eid)
                    issues.append(dict(context, code='non_pitcher_role_with_pitching', source_role=role))
                for field in FIELDS:
                    value = row['statistics'].get(field)
                    parsed = innings_to_outs(value) if field == 'innings_pitched' else integer(value)
                    if parsed is not None:
                        field_totals[field] += parsed
            for field in FIELDS:
                value = team_stats.get(field)
                parsed = innings_to_outs(value) if field == 'innings_pitched' else integer(value)
                if parsed is not None and parsed != field_totals[field]:
                    issues.append({'code': 'team_player_total_mismatch', 'event_id': eid,
                                   'team_id': tid, 'field': field,
                                   'team_value': parsed, 'player_sum': field_totals[field],
                                   'unit': 'outs' if field == 'innings_pitched' else 'count'})
        if game_missing_teams:
            missing_games.append({'event_id': eid, 'start_time': event['start_time'],
                                  'teams': event['competitors'],
                                  'missing_player_stats_team_ids': game_missing_teams,
                                  'reason': 'player_statistics_absent_in_saved_response'})
        else:
            player_game_count += 1

    team_output = []
    for tid, team in sorted(teams.items()):
        totals, partial = finish_stats(team.pop('acc'))
        game_ids = team.pop('team_stats_game_ids')
        absent_team_stats = sorted(eid for eid, row in summaries.items()
                                   if tid in {t['id'] for t in row['sport_event']['competitors']}
                                   and eid not in set(game_ids))
        team['run_differential'] = team['runs_scored'] - team['runs_allowed']
        decided = team['wins'] + team['losses']
        team['win_percentage'] = round(team['wins'] / decided, 6) if decided else None
        team['observed_statistics'] = totals
        team['observed_rates'] = rates(totals, partial)
        team['coverage'] = {
            'results_complete': not team['missing_score_game_ids'],
            'team_stats_games': len(game_ids), 'missing_team_stats_game_ids': absent_team_stats,
            'player_stats_games': team['games'] - len(team['missing_player_stats_game_ids']),
            'player_stats_complete': not team['missing_player_stats_game_ids'],
            'missing_or_invalid_field_counts_in_observed_records': partial,
            'team_stats_complete': not absent_team_stats and not partial,
        }
        team_output.append(team)

    player_output = []
    for (pid, tid), player in sorted(players.items()):
        totals, partial = finish_stats(player['acc'])
        missing_team_games = teams[tid]['missing_player_stats_game_ids']
        player_output.append({
            'season_id': season['id'], 'player_id': pid, 'team_id': tid,
            'team_name': teams[tid]['team_name'], 'player_name': sorted(player['names'])[0],
            'source_names': sorted(player['names']), 'source_role_record_counts': dict(player['source_roles']),
            'games_with_records': len(player['game_ids']), 'source_record_count': player['acc']['records'],
            'observed_statistics': totals, 'observed_rates': rates(totals, partial),
            'coverage': {
                'team_games_without_player_statistics': missing_team_games,
                'possibly_incomplete_due_to_team_missing_games': bool(missing_team_games),
                'missing_or_invalid_field_counts_in_observed_records': partial,
                'observed_fields_complete': not missing_team_games and not partial,
                'participation_in_missing_games': 'unknown' if missing_team_games else 'not_applicable',
            },
            'quality': {'non_pitcher_role_with_pitching_game_ids':
                        sorted(player['non_pitcher_role_with_pitching_game_ids'])},
        })

    metadata = {
        'generated_at': datetime.now(timezone.utc).isoformat(), 'season': season,
        'record_scope': 'regular_season_observed_aggregate',
        'target_games': len(summaries), 'raw_games': raw_count,
        'games_with_both_teams_player_statistics': player_game_count,
        'missing_raw_game_ids': raw_missing, 'missing_player_statistics_games': missing_games,
        'team_count': len(team_output), 'player_team_records': len(player_output),
        'unique_player_ids': len({p['player_id'] for p in player_output}),
        'source_player_record_count': sum(p['source_record_count'] for p in player_output),
        'quality_issue_counts': dict(Counter(i['code'] for i in issues)),
        'unavailable_statistics': UNAVAILABLE,
        'rules': {
            'team_results': 'Final scores from all closed regular-season games; summary fallback if raw missing.',
            'team_statistics': 'Sum original team statistics, not sums of player rows.',
            'player_key': 'season_id + player_id + team_id; preserve team stints and combine source roles.',
            'games_with_records': 'Number of games containing a player record; not official appearances.',
            'missing_values': 'Never replace missing/invalid values with zero. Totals sum observed valid values only; null if none.',
            'missing_game_players': 'Flag every observed player of the affected teams; actual participation is unknown. Unobserved players cannot be listed.',
            'innings_pitched': 'Baseball n.1/n.2 notation converted to outs, summed, then emitted as n.r string; original raw files retained.',
            'strikeouts': 'Ambiguous original field preserved; not exposed as pitcher_strikeouts.',
            'rates': 'Derived from observed counts only, not official season rates; null for incomplete required fields or zero denominator.',
            'quality': 'Source inconsistencies are reported without correction; complete coverage does not guarantee source accuracy.',
        },
    }
    destination = folder / 'aggregated'
    write_json(destination / 'team_season_stats.json', {'metadata': metadata, 'teams': team_output})
    write_json(destination / 'player_season_stats.json', {'metadata': metadata, 'players': player_output})
    write_json(destination / 'aggregation_report.json', {'metadata': metadata, 'issues': issues})
    return metadata, team_output, player_output


def main():
    parser = argparse.ArgumentParser(description='저장된 KBO 정규시즌 원본을 팀·선수별로 합산')
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parent.parent / 'kbo_data/kbo_2026_138278')
    args = parser.parse_args()
    metadata, _, _ = aggregate(args.input)
    print(json.dumps(metadata, ensure_ascii=False, indent=2))
    print(f'저장 위치: {args.input.resolve() / "aggregated"}')


if __name__ == '__main__':
    main()
