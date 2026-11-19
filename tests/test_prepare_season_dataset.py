import copy
import unittest

from tools.prepare_season_dataset import EVENTS, counts, league_baselines, profile, validate_lineups


def batter(pa=100):
    return {'plate_appearances': pa, 'at_bats': pa - 10, 'hits': 30,
            'doubles': 6, 'triples': 1, 'home_runs': 3, 'walks': 8, 'hit_by_pitch': 2,
            'batting_strikeouts': 20}


def pitcher():
    return {'batters_faced': 100, 'outs_pitched': 60, 'hits_allowed': 25,
            'home_runs_allowed': 2, 'walks_allowed': 10, 'hit_batters': 1,
            'pitcher_strikeouts': 20}


class DatasetTests(unittest.TestCase):
    def setUp(self):
        self.league = league_baselines([{'batting': batter(), 'pitching': pitcher()}])

    def test_plate_appearances_and_omitted_events_partition(self):
        c, missing = counts(batter(), 'batting')
        self.assertEqual(missing, [])
        self.assertEqual(c['single'], 20)
        self.assertEqual(c['hit_by_pitch'], 2)
        self.assertEqual(c['other_out'], 40)
        self.assertEqual(sum(c.values()), 100)

    def test_zero_sample_is_league_prior_and_source_stays_zero(self):
        stats = {key: 0 for key in batter()}
        pr = profile(stats, 'batting', self.league)
        self.assertEqual(pr['fallback_reason'], 'zero_denominator')
        self.assertEqual(pr['observed_weight'], 0)
        self.assertEqual(pr['probabilities'], self.league['batting'])
        self.assertEqual(stats['plate_appearances'], 0)

    def test_missing_field_is_not_zero_and_absent_role_is_null(self):
        stats = batter()
        stats['doubles'] = None
        pr = profile(stats, 'batting', self.league)
        self.assertEqual(pr['missing_fields'], ['doubles'])
        self.assertEqual(pr['fallback_reason'], 'missing_required_fields')
        self.assertIsNone(stats['doubles'])
        self.assertIsNone(profile(None, 'pitching', self.league))

    def test_prior_weight_and_pitcher_hit_split(self):
        pr = profile(batter(), 'batting', self.league)
        self.assertAlmostEqual(pr['observed_weight'], 1 / 3)
        self.assertAlmostEqual(sum(pr['probabilities'].values()), 1)
        pr = profile(pitcher(), 'pitching', self.league)
        self.assertTrue(pr['uses_league_hit_split'])
        self.assertEqual(set(pr['probabilities']), set(EVENTS))
        self.assertAlmostEqual(sum(pr['probabilities'].values()), 1)

    def test_invalid_counts_and_event_totals_block_export(self):
        for change in ({'hits': 101}, {'home_runs': 50}, {'walks': -1}, {'hits': True}):
            stats = batter()
            stats.update(change)
            with self.assertRaises(ValueError):
                profile(stats, 'batting', self.league)

    def test_membership_duplicates_and_missing_inputs_block_lineup(self):
        teams, players, lineups = [], [], []
        positions = ['C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF', 'DH']
        for i in range(10):
            tid = str(i)
            teams.append({'team_id': tid})
            lineup = {'team_id': tid, 'starting_pitcher_id': f'{i}-9', 'batting_order': []}
            for j in range(10):
                pid = f'{i}-{j}'
                players.append({'player_id': pid, 'assigned_team_id': tid,
                                'engine_profiles': {'batting': profile(batter(), 'batting', self.league),
                                                    'pitching': profile(pitcher(), 'pitching', self.league)}})
                if j < 9:
                    lineup['batting_order'].append({'order': j + 1, 'player_id': pid, 'position_code': positions[j]})
            lineups.append(lineup)
        self.assertEqual(validate_lineups(teams, players, lineups), 100)
        for mutation in ('membership', 'duplicate', 'missing'):
            ps, ls = copy.deepcopy(players), copy.deepcopy(lineups)
            if mutation == 'membership':
                ps[0]['assigned_team_id'] = None
            elif mutation == 'duplicate':
                ls[1]['batting_order'][0]['player_id'] = ls[0]['batting_order'][0]['player_id']
            else:
                ps[0]['engine_profiles']['batting']['fallback_reason'] = 'missing_required_fields'
            with self.assertRaises(ValueError):
                validate_lineups(teams, ps, ls)


if __name__ == '__main__':
    unittest.main()
