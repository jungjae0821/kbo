import unittest

from tools.build_lineups import POSITIONS, assign_positions, batting_order, eligible, select_pitcher


def batter(pid, positions, obp=.33, slg=.4, pa=500):
    return {'player_id': pid, 'batting': {'plate_appearances': pa, 'at_bats': 400,
            'on_base_percentage': obp, 'slugging_percentage': slg, 'home_runs': 10},
            'running': {'stolen_bases': 5}, 'fielding_by_position': [
                {'position': pos, 'starts': 80, 'games': 100, 'outs_fielded': 2000} for pos in positions]}


class LineupTests(unittest.TestCase):
    def test_global_assignment_preserves_scarce_position_and_unique_players(self):
        utility = batter('utility', ['포수', '1루수'], .4, .7)
        catcher = batter('catcher', ['포수'], .4, .6)
        weak_first = batter('weak', ['1루수'], .2, .2)
        dh = batter('dh', [], .38, .55)
        others = [batter(f'p{i}', [pos]) for i, pos in enumerate(POSITIONS[2:-1])]
        _, result = assign_positions([utility, catcher, weak_first, dh] + others, {'obp': .33, 'slg': .4})
        self.assertEqual(result['포수']['player_id'], 'catcher')
        self.assertEqual(result['1루수']['player_id'], 'utility')
        self.assertEqual(result['지명타자']['player_id'], 'dh')
        self.assertEqual(len({p['player_id'] for p in result.values()}), 9)
        ordered = batting_order(result, {'obp': .33, 'slg': .4})
        self.assertEqual(len({p['player_id'] for p in ordered}), 9)
        self.assertEqual(ordered[3]['player_id'], 'utility')

    def test_short_sample_and_one_game_fielding_do_not_qualify(self):
        self.assertFalse(eligible(batter('small', ['포수'], pa=20), '포수'))
        p = batter('oneoff', ['포수'])
        p['fielding_by_position'][0].update(starts=1, outs_fielded=3)
        self.assertFalse(eligible(p, '포수'))
        self.assertTrue(eligible(p, '지명타자'))

    def test_low_era_reliever_is_not_selected_as_starter(self):
        def pitcher(pid, era, outs, starts):
            return {'player_id': pid, 'pitching': {'earned_run_average': era, 'whip': 1.2, 'outs_pitched': outs},
                    'fielding_by_position': [{'position': '투수', 'starts': starts}]}
        candidates = [pitcher('closer', 1.0, 200, 0), pitcher('ace', 3.0, 330, 25), pitcher('workhorse', 4.0, 600, 30)]
        self.assertEqual(select_pitcher(candidates)['player_id'], 'ace')


if __name__ == '__main__':
    unittest.main()
