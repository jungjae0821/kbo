import contextlib
import copy
import io
import json
import tempfile
import unittest
from pathlib import Path

from tools.fetch_kbo import APIError, collect_games, pages, write_json


SEASON = {'id': 'sr:season:138278', 'year': '2026'}


def game(number, players=True, phase='regular season', status='closed'):
    return {
        'sport_event': {
            'id': f'sr:sport_event:{number}',
            'sport_event_context': {'stage': {'phase': phase}},
        },
        'sport_event_status': {'status': status},
        'statistics': {'totals': {'competitors': [{
            'id': 'team:1', 'players': [{
                'id': 'player:1', 'type': 'batter', 'statistics': {'hits': 0},
            }] if players else [],
        }]}},
    }


class FakeClient:
    def __init__(self, summaries, responses):
        self.summaries = summaries
        self.responses = responses
        self.details = []

    def get(self, path, **params):
        if path.endswith('/summaries'):
            start, limit = params['start'], params['limit']
            return {'summaries': self.summaries[start:start + limit]}
        event_id = path.split('/')[1]
        self.details.append(event_id)
        response = self.responses[event_id]
        if isinstance(response, BaseException):
            raise response
        return copy.deepcopy(response)


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.output = contextlib.ExitStack()
        self.output.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.output.enter_context(contextlib.redirect_stderr(io.StringIO()))
        self.addCleanup(self.output.close)

    def collect(self, client, **kwargs):
        return collect_games(client, SEASON, self.folder, **kwargs)

    def test_paginated_list_filters_duplicates_and_resumes_after_limit(self):
        matches = [game(n) for n in range(1, 203)]
        summaries = matches + [game(1), game(300, phase='playoffs'), game(301, status='not_started')]
        client = FakeClient(summaries, {g['sport_event']['id']: g for g in matches})
        report = self.collect(client, max_games=2)
        self.assertEqual(report['total_games'], 202)
        self.assertEqual(report['counts']['complete'], 2)
        self.assertEqual(report['counts']['pending'], 200)
        self.assertFalse(report['all_complete'])
        client.details.clear()
        report = self.collect(client)
        self.assertTrue(report['all_complete'])
        self.assertEqual(len(client.details), 200)
        self.assertNotIn('sr:sport_event:1', client.details)
        self.assertTrue((self.folder / 'raw/summaries_001.json').exists())

    def test_raw_cache_rebuilds_derived_file_and_corrupt_raw_is_retried(self):
        first, second = game(1), game(2)
        write_json(self.folder / 'sr_sport_event_1/game_raw.json', first)
        write_json(self.folder / 'sr_sport_event_1/player_stats.json', {'invalid': True})
        write_json(self.folder / 'sr_sport_event_2/game_raw.json', {'broken': True})
        client = FakeClient([first, second], {'sr:sport_event:2': second})
        self.assertTrue(self.collect(client)['all_complete'])
        self.assertEqual(client.details, ['sr:sport_event:2'])
        data = json.loads((self.folder / 'sr_sport_event_1/player_stats.json').read_text())
        self.assertEqual(data['players'][0]['statistics'], {'hits': 0})

    def test_missing_stats_and_failed_games_are_retried(self):
        client = FakeClient([game(1), game(2), game(3)], {
            'sr:sport_event:1': game(1, players=False),
            'sr:sport_event:2': APIError(404, 'HTTP 404'),
            'sr:sport_event:3': game(3),
        })
        report = self.collect(client)
        self.assertEqual(report['counts'], {'pending': 0, 'complete': 1, 'no_player_stats': 1, 'failed': 1})
        client.responses.update({'sr:sport_event:1': game(1), 'sr:sport_event:2': game(2)})
        client.details.clear()
        self.assertTrue(self.collect(client)['all_complete'])
        self.assertEqual(client.details, ['sr:sport_event:1', 'sr:sport_event:2'])

    def test_quota_error_stops_and_keeps_progress(self):
        client = FakeClient([game(1), game(2), game(3)], {
            'sr:sport_event:1': game(1), 'sr:sport_event:2': APIError(429, 'HTTP 429'),
        })
        with self.assertRaises(APIError):
            self.collect(client)
        report = json.loads((self.folder / 'collection_status.json').read_text())
        self.assertEqual(report['counts'], {'pending': 1, 'complete': 1, 'no_player_stats': 0, 'failed': 1})
        self.assertEqual(client.details, ['sr:sport_event:1', 'sr:sport_event:2'])

    def test_interruption_resumes_and_refresh_fetches_cached_game(self):
        client = FakeClient([game(1), game(2)], {
            'sr:sport_event:1': game(1), 'sr:sport_event:2': KeyboardInterrupt(),
        })
        with self.assertRaises(KeyboardInterrupt):
            self.collect(client)
        client.responses['sr:sport_event:2'] = game(2)
        client.details.clear()
        self.assertTrue(self.collect(client)['all_complete'])
        self.assertEqual(client.details, ['sr:sport_event:2'])
        client.details.clear()
        self.assertTrue(self.collect(client, refresh=True)['all_complete'])
        self.assertEqual(len(client.details), 2)

    def test_mismatched_detail_is_not_saved_as_complete(self):
        client = FakeClient([game(1)], {'sr:sport_event:1': game(2)})
        report = self.collect(client)
        self.assertEqual(report['counts']['failed'], 1)
        self.assertFalse((self.folder / 'sr_sport_event_1/game_raw.json').exists())

    def test_repeated_page_cannot_be_reported_as_complete(self):
        class RepeatingClient:
            def get(self, path, **params):
                return {'summaries': [game(1)] * 200}
        with self.assertRaises(RuntimeError):
            self.collect(RepeatingClient())
        report = json.loads((self.folder / 'collection_status.json').read_text())
        self.assertFalse(report['game_list_complete'])
        self.assertFalse(report['all_complete'])


if __name__ == '__main__':
    unittest.main()
