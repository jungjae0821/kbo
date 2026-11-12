import contextlib
import copy
import io
import tempfile
import unittest
from pathlib import Path

from tools.fetch_kbo import APIError, write_json
from tools.fetch_kbo_lineups import collect, read, validate_lineup


SEASON = {'id': 'sr:season:1', 'year': '2026'}
TEAMS = [{'id': f'sr:competitor:{n}', 'name': str(n), 'qualifier': side}
         for n, side in ((1, 'home'), (2, 'away'))]


def event(number):
    return {'id': f'sr:sport_event:{number}', 'start_time': '2026-05-09T08:00:00+00:00',
            'sport_event_context': {'season': copy.deepcopy(SEASON), 'stage': {'phase': 'regular season'}},
            'competitors': copy.deepcopy(TEAMS)}


def lineup(number=1):
    competitors = []
    for n, team in enumerate(TEAMS, 1):
        players = [{'id': f'sr:player:{n * 100 + slot}', 'name': f'player{slot}',
                    'type': 'IF', 'starter': True, 'order': slot} for slot in range(1, 10)]
        players.append({'id': f'sr:player:{n * 100}', 'name': 'pitcher', 'type': 'P', 'starter': True})
        competitors.append(dict(team, players=players))
    return {'sport_event': event(number), 'lineups': {'competitors': competitors}}


def index(data):
    return {t['id']: {p['id'] for p in t['players']} for t in data['lineups']['competitors']}


class FakeClient:
    def __init__(self, games, season_rows=None, detail=None):
        self.games = games
        self.rows = list(games.values()) if season_rows is None else season_rows
        self.detail = detail or {}
        self.calls = []

    def get(self, path, **params):
        self.calls.append((path, params))
        if path.startswith('seasons/'):
            return {'lineups': self.rows[params['start']:params['start'] + params['limit']]}
        if path.startswith('sport_events/'):
            eid = path.split('/')[1]
            data = self.detail.get(eid, self.games[eid])
            if isinstance(data, BaseException):
                raise data
            return copy.deepcopy(data)
        if path.startswith('competitors/'):
            tid = path.split('/')[1]
            team = next(t for t in lineup()['lineups']['competitors'] if t['id'] == tid)
            return {'competitor': {'id': tid}, 'players': team['players']}
        if path.startswith('players/'):
            return {'player': {'id': path.split('/')[1], 'type': 'OF'}}
        raise AssertionError(path)


class LineupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stack = contextlib.ExitStack()
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.addCleanup(self.stack.close)

    def inputs(self, count=2, extra_player=False):
        write_json(self.root / 'teams.json', {'season': SEASON, 'competitors': TEAMS})
        summaries = []
        games = {}
        for n in range(1, count + 1):
            data = lineup(n)
            raw = {'sport_event': event(n), 'sport_event_status': {'status': 'closed'},
                   'statistics': {'totals': {'competitors': data['lineups']['competitors']}}}
            if extra_player:
                raw['statistics']['totals']['competitors'][0]['players'].append({'id': 'sr:player:999', 'type': None})
                data = lineup(n)
            write_json(self.root / f'sr_sport_event_{n}/game_raw.json', raw)
            summaries.append({'sport_event': event(n), 'sport_event_status': {'status': 'closed'}})
            games[event(n)['id']] = data
        for page in range(0, len(summaries), 200):
            write_json(self.root / f'raw/summaries_{page // 200:03d}.json', {'summaries': summaries[page:page + 200]})
        if len(summaries) % 200 == 0:
            write_json(self.root / f'raw/summaries_{len(summaries) // 200:03d}.json', {'summaries': []})
        return games

    def test_substitute_slot_does_not_replace_starter(self):
        data = lineup()
        data['lineups']['competitors'][0]['players'].append({
            'id': 'sr:player:999', 'type': 'OF', 'starter': False, 'order': 1})
        result = validate_lineup(data, event(1), index(data))
        self.assertTrue(result['valid'])
        self.assertEqual(len(result['teams'][0]['starting_batters']), 9)
        self.assertEqual(result['teams'][0]['starting_batters'][0]['player_id'], 'sr:player:101')

    def test_bad_identity_duplicate_orders_and_missing_starter_are_rejected(self):
        for mutation in ('order', 'team', 'event', 'season', 'starter', 'pitcher', 'player', 'bool_order'):
            with self.subTest(mutation=mutation):
                data = lineup()
                p = data['lineups']['competitors'][0]['players']
                if mutation == 'order': p[0]['order'] = 2
                if mutation == 'bool_order': p[0]['order'] = True
                if mutation == 'team': data['lineups']['competitors'][0]['qualifier'] = 'away'
                if mutation == 'event': data['sport_event']['id'] = 'sr:sport_event:2'
                if mutation == 'season': data['sport_event']['sport_event_context']['season']['id'] = 'sr:season:99'
                if mutation == 'starter': p[0]['starter'] = 'true'
                if mutation == 'pitcher': p[-1]['starter'] = False
                if mutation == 'player': p[0]['id'] = p[1]['id']
                self.assertFalse(validate_lineup(data, event(1), index(lineup()))['valid'])

    def test_missing_stats_is_warning_but_opposing_team_id_is_error(self):
        self.assertTrue(validate_lineup(lineup(), event(1), {})['valid'])
        data = lineup()
        data['lineups']['competitors'][0]['players'][0]['id'] = 'sr:player:201'
        self.assertFalse(validate_lineup(data, event(1), index(lineup()))['valid'])

    def test_schema_errors_are_reported_without_crashing(self):
        for malformed in (None, [], {'sport_event': None}, {'sport_event': event(1), 'lineups': []}):
            self.assertFalse(validate_lineup(malformed, event(1), {})['valid'])

    def test_season_pages_repair_missing_game_and_resume(self):
        games = self.inputs()
        client = FakeClient(games, season_rows=[games['sr:sport_event:1']])
        report = collect(client, self.root)
        self.assertTrue(report['all_complete'])
        self.assertTrue(any(p == 'sport_events/sr:sport_event:2/lineups' for p, _ in client.calls))
        client.calls.clear()
        self.assertTrue(collect(client, self.root)['all_complete'])
        self.assertEqual(client.calls, [])

    def test_pagination_limit_is_100_and_profile_fallback_matches_id(self):
        games = self.inputs(101, extra_player=True)
        client = FakeClient(games)
        report = collect(client, self.root)
        self.assertTrue(report['all_complete'])
        season_calls = [(p, args) for p, args in client.calls if p.startswith('seasons/')]
        self.assertEqual([a['start'] for _, a in season_calls], [0, 100])
        self.assertTrue(all(a['limit'] == 100 for _, a in season_calls))
        self.assertTrue(any(p == 'players/sr:player:999/profile' for p, _ in client.calls))
        positions = read(self.root / 'supplemental/player_positions.json')['players']
        p = next(p for p in positions if p['player_id'] == 'sr:player:999')
        self.assertEqual(p['positions_observed'], ['OF'])

    def test_quota_stop_persists_incomplete_report_then_resumes(self):
        games = self.inputs()
        client = FakeClient(games, season_rows=[], detail={'sr:sport_event:2': APIError(429, 'HTTP 429')})
        with self.assertRaises(APIError):
            collect(client, self.root)
        report = read(self.root / 'supplemental/collection_status.json')
        self.assertFalse(report['all_complete'])
        self.assertEqual(report['valid_lineup_games'], 1)
        repaired = FakeClient(games, season_rows=[])
        self.assertTrue(collect(repaired, self.root)['all_complete'])
        self.assertFalse(any(p == 'sport_events/sr:sport_event:1/lineups' for p, _ in repaired.calls))

    def test_conflicting_duplicate_requires_individual_confirmation(self):
        games = self.inputs(1)
        bad = copy.deepcopy(games['sr:sport_event:1'])
        bad['lineups']['competitors'][0]['players'][0]['name'] = 'different snapshot'
        client = FakeClient(games, season_rows=[games['sr:sport_event:1'], bad])
        self.assertTrue(collect(client, self.root)['all_complete'])
        self.assertTrue(any(p.startswith('sport_events/') for p, _ in client.calls))

    def test_wrong_player_profile_id_is_not_joined_by_name(self):
        games = self.inputs(1, extra_player=True)

        class WrongProfileClient(FakeClient):
            def get(self, path, **params):
                if path == 'players/sr:player:999/profile':
                    return {'player': {'id': 'sr:player:998', 'name': 'same name', 'type': 'OF'}}
                return super().get(path, **params)

        report = collect(WrongProfileClient(games), self.root)
        self.assertFalse(report['all_complete'])
        self.assertEqual(report['existing_player_ids_without_position'], ['sr:player:999'])

    def test_invalid_lineup_cannot_be_complete_when_repair_limit_is_reached(self):
        games = self.inputs()
        report = collect(FakeClient(games, season_rows=[]), self.root, max_games=1)
        self.assertFalse(report['all_complete'])
        self.assertEqual(report['invalid_or_missing_game_ids'], ['sr:sport_event:2'])
        report = collect(FakeClient(games, season_rows=[]), self.root, max_games=1)
        self.assertTrue(report['all_complete'])


if __name__ == '__main__':
    unittest.main()
