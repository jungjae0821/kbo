import json
import tempfile
import unittest
from pathlib import Path

from tools.aggregate_kbo import aggregate, innings_to_outs
from tools.fetch_kbo import write_json


SEASON = {'id': 'sr:season:1', 'year': '2026'}


def player(pid='p1', role='pitcher', **stats):
    return {'id': pid, 'name': pid, 'type': role, 'statistics': stats}


def game(number, home_players=None, away_players=None):
    return {
        'sport_event': {
            'id': f'sr:sport_event:{number}', 'start_time': '2026-05-09T08:00:00+00:00',
            'sport_event_context': {'season': SEASON, 'stage': {'phase': 'regular season'}},
            'competitors': [{'id': 'A', 'name': 'A', 'qualifier': 'home'},
                            {'id': 'B', 'name': 'B', 'qualifier': 'away'}],
        },
        'sport_event_status': {'status': 'closed', 'home_score': 1, 'away_score': 3},
        'statistics': {'totals': {'competitors': [
            {'id': 'A', 'statistics': {'hits': 2}, 'players': home_players or []},
            {'id': 'B', 'statistics': {'hits': 3}, 'players': away_players or []},
        ]}},
    }


class AggregateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        write_json(self.root / 'teams.json', {
            'season': SEASON, 'competitors': [{'id': 'A', 'name': 'A'}, {'id': 'B', 'name': 'B'}],
        })

    def save(self, games, extra_summaries=None):
        for g in games:
            folder = self.root / g['sport_event']['id'].replace(':', '_')
            write_json(folder / 'game_raw.json', g)
        write_json(self.root / 'raw/summaries_000.json', {'summaries': games + (extra_summaries or [])})

    def test_missing_game_flags_and_baseball_innings(self):
        first = game(1, [player(innings_pitched=0.2, earned_runs=1, at_bats=0)],
                     [player('p2', 'batter', at_bats=3, hits=1)])
        second = game(2, [player(innings_pitched=0.1, earned_runs=0, at_bats=0)],
                      [player('p2', 'batter', at_bats=4, hits=2)])
        third = game(3)
        third.pop('statistics')
        self.save([first, second, third], [first])
        meta, teams, players = aggregate(self.root)
        self.assertEqual(meta['target_games'], 3)  # Duplicate ID counted once.
        self.assertEqual(meta['games_with_both_teams_player_statistics'], 2)
        self.assertEqual(teams[0]['losses'], 3)
        self.assertEqual(teams[0]['runs_allowed'], 9)
        self.assertEqual(teams[0]['observed_statistics']['hits'], 4)  # Team totals, not player sums.
        self.assertFalse(teams[0]['coverage']['team_stats_complete'])
        pitcher = next(p for p in players if p['player_id'] == 'p1')
        self.assertEqual(pitcher['observed_statistics']['innings_pitched'], '1.0')
        self.assertEqual(pitcher['observed_statistics']['outs_pitched'], 3)
        self.assertEqual(pitcher['observed_rates']['earned_run_average'], 9)
        self.assertIsNone(pitcher['observed_statistics']['hits'])
        self.assertEqual(pitcher['coverage']['team_games_without_player_statistics'], ['sr:sport_event:3'])
        self.assertTrue(pitcher['coverage']['possibly_incomplete_due_to_team_missing_games'])
        batter = next(p for p in players if p['player_id'] == 'p2')
        self.assertEqual(batter['observed_rates']['batting_average'], round(3 / 7, 6))

    def test_invalid_values_are_partial_not_zero_and_source_roles_are_preserved(self):
        self.save([
            game(1, [player(role='batter', innings_pitched=1.1, at_bats='-', hits=1)], [player('p2', hits=0)]),
            game(2, [player(role='pitcher', innings_pitched=0.2, at_bats=2, hits=1)], [player('p2', hits=0)]),
        ])
        meta, _, players = aggregate(self.root)
        p = next(p for p in players if p['player_id'] == 'p1')
        self.assertEqual(p['observed_statistics']['at_bats'], 2)
        self.assertEqual(p['observed_statistics']['innings_pitched'], '2.0')
        self.assertIsNone(p['observed_rates']['batting_average'])
        self.assertEqual(p['source_role_record_counts'], {'batter': 1, 'pitcher': 1})
        self.assertEqual(p['coverage']['missing_or_invalid_field_counts_in_observed_records']['at_bats'], 1)
        self.assertEqual(meta['quality_issue_counts']['invalid_stat_value'], 1)
        self.assertEqual(meta['quality_issue_counts']['non_pitcher_role_with_pitching'], 1)

    def test_transfer_stints_remain_separate(self):
        self.save([game(1, [player(hits=1)], [player('p2', hits=2)]),
                   game(2, [player('p2', hits=3)], [player(hits=4)])])
        meta, _, players = aggregate(self.root)
        self.assertEqual(meta['unique_player_ids'], 2)
        self.assertEqual(meta['player_team_records'], 4)
        stints = {p['team_id']: p['observed_statistics']['hits'] for p in players if p['player_id'] == 'p1'}
        self.assertEqual(stints, {'A': 1, 'B': 4})

    def test_duplicate_player_record_is_rejected(self):
        self.save([game(1, [player(hits=1), player(hits=1)])])
        with self.assertRaisesRegex(ValueError, '중복'):
            aggregate(self.root)

    def test_innings_rejects_invalid_and_missing_values(self):
        self.assertEqual(innings_to_outs('6.2'), 20)
        self.assertEqual(innings_to_outs(0), 0)
        for bad in (None, '-', 1.3, -1, 'NaN', True):
            self.assertIsNone(innings_to_outs(bad))


if __name__ == '__main__':
    unittest.main()
