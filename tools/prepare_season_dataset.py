"""Export a versioned, validated offline input contract for the Dart engine."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

if __package__:
    from .fetch_kbo import write_json
else:  # Also support python tools/prepare_season_dataset.py
    from fetch_kbo import write_json

EVENTS = ('strikeout', 'walk', 'hit_by_pitch', 'single', 'double', 'triple', 'home_run', 'other_out')
BAT_FIELDS = ('plate_appearances', 'at_bats', 'hits', 'doubles', 'triples',
              'home_runs', 'walks', 'hit_by_pitch', 'batting_strikeouts')
PITCH_FIELDS = ('batters_faced', 'outs_pitched', 'hits_allowed', 'home_runs_allowed',
                'walks_allowed', 'hit_batters', 'pitcher_strikeouts')
POSITIONS = {'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF', 'DH'}
PRIOR_PA = 200
PRIOR_BF = 200


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':'), allow_nan=False).encode('utf-8')).hexdigest()


def valid_count(value):
    return type(value) is int and value >= 0


def normalize(values):
    if any(not math.isfinite(v) or v < 0 for v in values.values()) or sum(values.values()) <= 0:
        raise ValueError('Invalid probability vector')
    total = sum(values.values())
    return {event: values[event] / total for event in EVENTS}


def counts(stats, role, hit_split=None):
    fields = BAT_FIELDS if role == 'batting' else PITCH_FIELDS
    missing = [f for f in fields if stats.get(f) is None]
    if missing:
        return None, missing
    if any(not valid_count(stats[f]) for f in fields):
        raise ValueError(f'Invalid {role} count')
    if role == 'batting':
        n, hits, hr, bb, hbp, k = (stats[f] for f in
                                   ('plate_appearances', 'hits', 'home_runs', 'walks',
                                    'hit_by_pitch', 'batting_strikeouts'))
        double, triple = stats['doubles'], stats['triples']
        if hits > stats['at_bats'] or stats['at_bats'] > n:
            raise ValueError('Inconsistent PA/AB/H')
    else:
        n, hits, hr, bb, hbp, k = (stats[f] for f in
                                   ('batters_faced', 'hits_allowed', 'home_runs_allowed',
                                    'walks_allowed', 'hit_batters', 'pitcher_strikeouts'))
        double, triple = stats.get('doubles_allowed'), stats.get('triples_allowed')
        if double is None or triple is None:
            # The caller supplies an explicit documented league non-HR hit split.
            if hit_split is None:
                raise ValueError('League hit split required')
            double = (hits - hr) * hit_split['double']
            triple = (hits - hr) * hit_split['triple']
        elif not valid_count(double) or not valid_count(triple):
            raise ValueError('Invalid extra-base hits allowed')
    single = hits - hr - double - triple
    other = n - hits - bb - hbp - k
    if min(single, other, hits - hr) < -1e-9:
        raise ValueError(f'Inconsistent {role} event partition')
    if n == 0 and (hits or hr or bb or hbp or k or double or triple):
        raise ValueError('Nonzero events with zero denominator')
    return dict(zip(EVENTS, (k, bb, hbp, max(0, single), double, triple, hr, max(0, other)))), []


def league_baselines(players):
    batting = {e: 0 for e in EVENTS}
    usable_batters = 0
    for p in players:
        if p.get('batting') is None:
            continue
        values, missing = counts(p['batting'], 'batting')
        if missing or not p['batting']['plate_appearances']:
            continue
        usable_batters += 1
        for e in EVENTS:
            batting[e] += values[e]
    non_hr = sum(batting[e] for e in ('single', 'double', 'triple'))
    if not non_hr:
        raise ValueError('No league non-HR hit sample')
    split = {e: batting[e] / non_hr for e in ('single', 'double', 'triple')}
    pitching = {e: 0 for e in EVENTS}
    usable_pitchers = 0
    for p in players:
        if p.get('pitching') is None:
            continue
        values, missing = counts(p['pitching'], 'pitching', split)
        if missing or not p['pitching']['batters_faced']:
            continue
        usable_pitchers += 1
        for e in EVENTS:
            pitching[e] += values[e]
    return {'batting': normalize(batting), 'pitching': normalize(pitching),
            'non_home_run_hit_split': split,
            'batting_sample_pa': sum(batting.values()),
            'pitching_sample_bf': sum(pitching.values()),
            'batting_player_count': usable_batters, 'pitching_player_count': usable_pitchers}


def profile(stats, role, league):
    if stats is None:
        return None
    values, missing = counts(stats, role, league['non_home_run_hit_split'])
    denominator = 'plate_appearances' if role == 'batting' else 'batters_faced'
    n = stats.get(denominator)
    prior = PRIOR_PA if role == 'batting' else PRIOR_BF
    baseline = league[role]
    fallback = 'missing_required_fields' if missing else ('zero_denominator' if n == 0 else None)
    if fallback:
        probabilities = baseline.copy()
        weight = 0.0
    else:
        probabilities = normalize({e: (values[e] + prior * baseline[e]) / (n + prior) for e in EVENTS})
        weight = n / (n + prior)
    return {'sample_size': n, 'prior_sample_size': prior, 'observed_weight': weight,
            'missing_fields': missing, 'fallback_reason': fallback,
            'uses_league_hit_split': role == 'pitching' and
                (stats.get('doubles_allowed') is None or stats.get('triples_allowed') is None),
            'probabilities': probabilities}


def validate_lineups(teams, players, lineups):
    team_by_id = {t['team_id']: t for t in teams}
    by_id = {p['player_id']: p for p in players}
    if len(team_by_id) != 10 or len(by_id) != len(players):
        raise ValueError('Expected ten unique teams and unique player IDs')
    if len(lineups) != 10 or {t['team_id'] for t in lineups} != set(team_by_id):
        raise ValueError('Lineup team mismatch')
    used = set()
    for lineup in lineups:
        batters = lineup['batting_order']
        if len(batters) != 9 or sorted(b['order'] for b in batters) != list(range(1, 10)):
            raise ValueError('Invalid batting order')
        if {b['position_code'] for b in batters} != POSITIONS:
            raise ValueError('Invalid positions')
        entries = [(b['player_id'], 'batting') for b in batters]
        entries.append((lineup['starting_pitcher_id'], 'pitching'))
        for pid, role in entries:
            if pid in used or pid not in by_id:
                raise ValueError('Duplicate or unknown lineup player')
            used.add(pid)
            p = by_id[pid]
            if p['assigned_team_id'] != lineup['team_id']:
                raise ValueError('Player membership mismatch')
            pr = p['engine_profiles'][role]
            if pr is None or pr['fallback_reason'] is not None:
                raise ValueError('Lineup player lacks usable required statistics')
            probs = pr['probabilities']
            if set(probs) != set(EVENTS) or any(not math.isfinite(v) or not 0 <= v <= 1 for v in probs.values()):
                raise ValueError('Invalid lineup probabilities')
            if not math.isclose(sum(probs.values()), 1, abs_tol=1e-12):
                raise ValueError('Probability sum mismatch')
    return len(used)


def build(folder):
    names = ('corrected_team_season_stats.json', 'corrected_player_season_stats.json', 'team_lineups.json')
    sources = {}
    hashes = {}
    for name in names:
        raw = (folder / 'aggregated' / name).read_bytes()
        sources[name] = json.loads(raw)
        hashes[name] = hashlib.sha256(raw).hexdigest()
    ts, ps, ls = (sources[name] for name in names)
    season = ps['metadata']['season']
    if any(s['metadata']['season'] != season for s in (ts, ls)):
        raise ValueError('Source season mismatch')
    if ls['metadata']['source_sha256'] != hashes[names[1]]:
        raise ValueError('Stale lineups: rerun python -m tools.build_lineups')
    teams = copy.deepcopy(ts['teams'])
    label_map = {t['official_team_name']: t['team_id'] for t in teams}
    if len(label_map) != len(teams):
        raise ValueError('Duplicate official team labels')
    league = league_baselines(ps['players'])
    players = []
    for original in ps['players']:
        p = copy.deepcopy(original)
        if p['player_id'] != 'kbo:player:' + p['kbo_player_id']:
            raise ValueError('Official player ID mismatch')
        labels = list(dict.fromkeys(p['official_team_names']))
        assigned = label_map.get(labels[0]) if len(labels) == 1 else None
        p['assigned_team_id'] = assigned
        p['membership_status'] = 'official_season_label' if assigned else 'unresolved_excluded_from_lineups'
        p['record_scope'] = 'season_total_not_team_stint'
        p['engine_profiles'] = {role: profile(p.get(role), role, league) for role in ('batting', 'pitching')}
        players.append(p)
    lineups = [{'team_id': t['team_id'], 'starting_pitcher_id': t['starting_pitcher']['player_id'],
                'batting_order': [{k: b[k] for k in ('order', 'player_id', 'position_code')}
                                  for b in t['batting_order']]} for t in ls['teams']]
    selected = validate_lineups(teams, players, lineups)
    for t in teams:
        t['roster_player_ids'] = [p['player_id'] for p in players if p['assigned_team_id'] == t['team_id']]
        t['membership_notice'] = '공식 시즌 표의 팀 분류입니다. 성적은 시즌 전체 합계이며 해당 팀 소속 기간만의 기록이나 현재 등록 명단을 뜻하지 않습니다.'
    result = {'schema_version': '1.0.0', 'season': season,
              'sources': hashes, 'rules': {'version': '2.0.0', 'events': list(EVENTS),
                  'prior_pa': PRIOR_PA, 'prior_bf': PRIOR_BF,
                  'matchup': 'arithmetic_mean_then_normalize', 'max_innings': 11,
                  'pitcher_usage': 'starter_for_entire_game',
                  'membership': 'unique_official_season_label_no_split_no_duplicate',
                  'omitted_events': 'sacrifices/errors/fielder choices count as other_out; double plays and runs on outs are situational in the engine; no steals'},
              'league_baselines': league, 'teams': teams, 'players': players, 'lineups': lineups}
    result['data_version'] = str(season['year']) + '-' + digest(result)
    report = {'data_version': result['data_version'], 'validation_status': 'passed',
              'team_count': len(teams), 'player_count': len(players), 'lineup_count': len(lineups),
              'unique_selected_players': selected,
              'unassigned_player_ids': [p['player_id'] for p in players if not p['assigned_team_id']],
              'fallback_profiles': [{'player_id': p['player_id'], 'role': role,
                                     'reason': pr['fallback_reason'], 'missing_fields': pr['missing_fields']}
                                    for p in players for role, pr in p['engine_profiles'].items()
                                    if pr and pr['fallback_reason']],
              'lineup_required_fields_valid': True, 'lineup_membership_valid': True,
              'lineup_unique_across_teams': True, 'source_hashes_valid': True,
              'scope': 'Offline data contract validation only; Dart engine and Flutter app are not implemented.'}
    write_json(folder / 'app/season_dataset.json', result)
    write_json(folder / 'app/dataset_validation_report.json', report)
    return report


def main():
    parser = argparse.ArgumentParser(description='Dart 입력용 시즌 JSON 생성·검증 (네트워크 호출 없음)')
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parent.parent / 'kbo_data/kbo_2026_138278')
    args = parser.parse_args()
    report = build(args.input)
    summary = {k: v for k, v in report.items() if k != 'fallback_profiles'}
    summary['fallback_profile_count'] = len(report['fallback_profiles'])
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
