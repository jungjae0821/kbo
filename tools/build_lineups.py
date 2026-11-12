"""Build reproducible fantasy lineups from official KBO season records."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

if __package__:
    from .fetch_kbo import write_json
else:  # Also support python tools/build_lineups.py
    from fetch_kbo import write_json

POSITIONS = ('포수', '1루수', '2루수', '3루수', '유격수', '좌익수', '중견수', '우익수', '지명타자')
CODES = ('C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF', 'DH')
MIN_PA = 144
MIN_POSITION_STARTS = 10
MIN_POSITION_OUTS = 270
MIN_PITCHING_OUTS = 300  # 100 innings, a selection rule rather than an official qualification.
MIN_PITCHING_STARTS = 20
PRIOR_PA = 200


def pitching_starts(player):
    return sum(f['starts'] for f in player.get('fielding_by_position', []) if f['position'] == '투수')


def select_pitcher(players):
    candidates = [p for p in players if p.get('pitching')
                  and p['pitching']['outs_pitched'] >= MIN_PITCHING_OUTS
                  and pitching_starts(p) >= MIN_PITCHING_STARTS
                  and p['pitching'].get('earned_run_average') is not None
                  and p['pitching'].get('whip') is not None]
    if not candidates:
        raise ValueError('선발 20회·100이닝 이상 투수 후보가 없습니다. 기준 검토가 필요합니다.')
    return min(candidates, key=lambda p: (p['pitching']['earned_run_average'], p['pitching']['whip'],
                                          -p['pitching']['outs_pitched'], p['player_id']))


def fielding(player, position):
    return next((f for f in player.get('fielding_by_position', []) if f['position'] == position), None)


def eligible(player, position):
    b = player.get('batting')
    if not b or b.get('plate_appearances', 0) < MIN_PA or not b.get('at_bats'):
        return False
    if b.get('on_base_percentage') is None or b.get('slugging_percentage') is None:
        return False
    if position == '지명타자':
        return True
    f = fielding(player, position)
    return bool(f and (f['starts'] >= MIN_POSITION_STARTS or f['outs_fielded'] >= MIN_POSITION_OUTS))


def adjusted_rates(player, baseline):
    b = player['batting']
    pa = b['plate_appearances']
    obp = (pa * b['on_base_percentage'] + PRIOR_PA * baseline['obp']) / (pa + PRIOR_PA)
    slg = (pa * b['slugging_percentage'] + PRIOR_PA * baseline['slg']) / (pa + PRIOR_PA)
    return {'obp': obp, 'slg': slg, 'ops': obp + slg}


def assignment_score(player, position, baseline):
    value = adjusted_rates(player, baseline)['ops']
    value += 0.01 * min(player['batting']['plate_appearances'] / 600, 1)
    f = fielding(player, position)
    if f:
        value += 0.02 * min(f['starts'] / 80, 1)
    return value


def assign_positions(players, baseline):
    """Exact maximum-score assignment over nine slots; a player can fill one slot."""
    if len({p['player_id'] for p in players}) != len(players):
        raise ValueError('후보 선수 ID가 중복됩니다.')
    dp = {0: (0.0, {})}
    for player in sorted(players, key=lambda p: p['player_id']):
        previous = list(dp.items())
        for mask, (value, assignment) in previous:
            for i, position in enumerate(POSITIONS):
                if mask & (1 << i) or not eligible(player, position):
                    continue
                next_mask = mask | (1 << i)
                score = value + assignment_score(player, position, baseline)
                if next_mask not in dp or score > dp[next_mask][0] + 1e-12:
                    dp[next_mask] = score, dict(assignment, **{position: player})
    full = (1 << len(POSITIONS)) - 1
    if full not in dp:
        raise ValueError('포지션 경험·타석 기준을 충족하는 중복 없는 주전 9명을 구성할 수 없습니다.')
    return dp[full]


def batting_order(assignment, baseline):
    remaining = list(assignment.values())
    slots = {}

    def take(slot, primary, secondary):
        p = max(remaining, key=lambda p: (primary(p), secondary(p),
                                         p['batting']['plate_appearances'], p['player_id']))
        slots[slot] = p
        remaining.remove(p)

    rate = lambda p: adjusted_rates(p, baseline)
    take(4, lambda p: rate(p)['slg'], lambda p: p['batting']['home_runs'])
    take(2, lambda p: rate(p)['ops'], lambda p: rate(p)['obp'])
    take(1, lambda p: rate(p)['obp'], lambda p: (p.get('running') or {}).get('stolen_bases', 0))
    take(3, lambda p: rate(p)['ops'], lambda p: rate(p)['slg'])
    take(5, lambda p: rate(p)['slg'], lambda p: rate(p)['ops'])
    for slot in (6, 7, 8, 9):
        take(slot, lambda p: rate(p)['ops'], lambda p: rate(p)['obp'])
    return [slots[i] for i in range(1, 10)]


def build(folder):
    source_path = folder / 'aggregated/corrected_player_season_stats.json'
    raw = source_path.read_bytes()
    source = json.loads(raw)
    teams = json.loads((folder / 'aggregated/corrected_team_season_stats.json').read_text(encoding='utf-8'))
    players = source['players']
    hitters = [p for p in players if p.get('batting') and p['batting']['plate_appearances']
               and p['batting'].get('on_base_percentage') is not None and p['batting'].get('slugging_percentage') is not None]
    total_pa = sum(p['batting']['plate_appearances'] for p in hitters)
    baseline = {name: sum(p['batting'][field] * p['batting']['plate_appearances'] for p in hitters) / total_pa
                for name, field in [('obp', 'on_base_percentage'), ('slg', 'slugging_percentage')]}
    output = []
    for team in teams['teams']:
        short = team['official_team_name']
        roster = [p for p in players if short in p['official_team_names']]
        sp = select_pitcher(roster)
        objective, assignment = assign_positions([p for p in roster if p['player_id'] != sp['player_id']], baseline)
        order = batting_order(assignment, baseline)
        positions = {p['player_id']: position for position, p in assignment.items()}
        batters = []
        for number, player in enumerate(order, 1):
            pos = positions[player['player_id']]
            experience = fielding(player, pos)
            batters.append({'order': number, 'player_id': player['player_id'], 'kbo_player_id': player['kbo_player_id'],
                            'player_name': player['player_name'], 'position': pos,
                            'position_code': CODES[POSITIONS.index(pos)], 'batting': player['batting'],
                            'running': player.get('running'), 'adjusted_rates': adjusted_rates(player, baseline),
                            'fielding_evidence': experience if pos != '지명타자' else None})
        assert len({p['player_id'] for p in batters}) == 9
        assert {p['position'] for p in batters} == set(POSITIONS)
        assert sp['player_id'] not in {p['player_id'] for p in batters}
        output.append({'team_id': team['team_id'], 'team_name': team['team_name'],
                       'official_team_name': short, 'assignment_score': objective,
                       'starting_pitcher': {'player_id': sp['player_id'], 'kbo_player_id': sp['kbo_player_id'],
                                            'player_name': sp['player_name'], 'season_starts': pitching_starts(sp),
                                            'pitching': sp['pitching']}, 'batting_order': batters,
                       'validation': {'unique_batters': True, 'all_defensive_positions_filled': True,
                                      'pitcher_separate_from_batters': True, 'all_players_match_team': True}})
    all_ids = [p['player_id'] for t in output for p in t['batting_order']]
    all_ids += [t['starting_pitcher']['player_id'] for t in output]
    if len(set(all_ids)) != len(all_ids):
        raise ValueError('팀 간 선수 ID가 중복됩니다. 이적 구간 확인이 필요합니다.')
    result = {
        'metadata': {'created_at': datetime.now(timezone.utc).isoformat(), 'season': source['metadata']['season'],
                     'purpose': 'fantasy_starting_lineups_from_final_season_stats', 'algorithm_version': '1.0',
                     'source_file': source_path.name, 'source_sha256': hashlib.sha256(raw).hexdigest(),
                     'team_count': len(output), 'league_pa_weighted_baseline': baseline,
                     'rules': {
                         'pitcher': 'At least 20 starts and 100 innings; lowest official ERA, then WHIP, then most outs.',
                         'batters': 'At least 144 PA and positive AB. No injury, handedness or opponent adjustment.',
                         'defense': 'Eight fielders plus DH. A fielding slot needs >=10 starts or >=30 defensive innings at that exact position.',
                         'assignment': 'Maximize sum of shrunken OPS + 0.01*min(PA/600,1) + 0.02*min(position starts/80,1). Player used once.',
                         'shrinkage': 'OBP and SLG each shrunk toward league PA-weighted rate using 200 prior PA.',
                         'batting_order': 'Select #4 by adjusted SLG, #2 by adjusted OPS, #1 by adjusted OBP, #3 by adjusted OPS, #5 by adjusted SLG, #6-9 by adjusted OPS. Remove each chosen hitter before next selection.',
                         'scope': 'A reproducible fantasy lineup, not an actual historical lineup or a proven run-maximizing order.',
                         'team_membership': 'Official season table team labels; not a separately verified end-of-season active roster.',
                     }}, 'teams': output}
    write_json(folder / 'aggregated/team_lineups.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description='KBO 공식 시즌 성적으로 팀별 선발·주전·타순 구성')
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parent.parent / 'kbo_data/kbo_2026_138278')
    args = parser.parse_args()
    result = build(args.input)
    for team in result['teams']:
        sp = team['starting_pitcher']
        order = ' → '.join(f"{p['order']}.{p['player_name']}({p['position_code']})" for p in team['batting_order'])
        print(f"{team['official_team_name']} | 선발 {sp['player_name']} (ERA {sp['pitching']['earned_run_average']:.2f}) | {order}")


if __name__ == '__main__':
    main()
