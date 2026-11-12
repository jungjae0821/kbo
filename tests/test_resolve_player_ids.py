import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch

from tools.fetch_kbo import APIError
from tools.resolve_player_ids import aliases, bio_from_html, choose_bio, collect_profiles, read


class IdentityTests(unittest.TestCase):
    def test_alias_is_only_a_candidate(self):
        self.assertIn('황재균', aliases('황, 재균'))
        self.assertIn('김성윤', aliases('성윤김'))
        self.assertIn('오스틴', aliases('딘, 오스틴'))

    def test_profile_birthday_and_height_are_parsed(self):
        html = ('<span id="profile_lblName">김선수</span>'
                '<span id="profile_lblBirthday">2000년 03월 04일</span>'
                '<span id="profile_lblHeightWeight">183cm/85kg</span>')
        bio = bio_from_html(html, '12345')
        self.assertEqual(bio['date_of_birth'], '2000-03-04')
        self.assertEqual(bio['height'], 183)

    def test_dob_without_other_identity_evidence_is_rejected(self):
        profile = {'player': {'date_of_birth': '2000-01-01', 'name': 'different'}}
        bio = {'kbo_player_id': '1', 'date_of_birth': '2000-01-01', 'name': '김선수', 'height': 180}
        result, _ = choose_bio(profile, [bio], {'names': {'different'}}, {})
        self.assertIsNone(result)

    def test_same_name_players_are_disambiguated_by_birth_date(self):
        bios = [{'kbo_player_id': '1', 'date_of_birth': '2000-01-01', 'name': '김선수'},
                {'kbo_player_id': '2', 'date_of_birth': '2001-01-01', 'name': '김선수'}]
        profile = {'player': {'date_of_birth': '2001-01-01', 'name': '김선수'}}
        result, reason = choose_bio(profile, bios, {'names': {'김선수'}}, {})
        self.assertEqual(result[0]['kbo_player_id'], '2')
        self.assertIsNone(reason)

    def test_duplicate_name_and_birthday_remains_unresolved(self):
        bios = [{'kbo_player_id': str(i), 'date_of_birth': '2000-01-01', 'name': '김선수'} for i in (1, 2)]
        profile = {'player': {'date_of_birth': '2000-01-01', 'name': '김선수'}}
        result, reason = choose_bio(profile, bios, {'names': {'김선수'}}, {})
        self.assertIsNone(result)
        self.assertEqual(reason, 'bio_candidates_ambiguous')

    def test_missing_provider_profile_does_not_abort_other_profiles(self):
        rows = [{'verified': False, 'provider_player_id': 'sr:player:1', 'provider_names': []},
                {'verified': False, 'provider_player_id': 'sr:player:2', 'provider_names': []}]
        with tempfile.TemporaryDirectory() as tmp, patch('tools.resolve_player_ids.Client') as client:
            client.return_value.get.side_effect = [APIError(404, 'HTTP 404'),
                {'player': {'id': 'sr:player:2', 'date_of_birth': '2000-01-01'}}]
            collect_profiles(Path(tmp), [], {}, rows, 'test-key', 0)
            self.assertEqual(client.return_value.get.call_count, 2)
            self.assertTrue((Path(tmp) / 'official/identity/provider_profiles/sr_player_2.json').exists())

    def test_quota_error_stops_api_but_runs_official_stage(self):
        rows = [{'verified': False, 'provider_player_id': 'sr:player:1', 'provider_names': []}]
        with tempfile.TemporaryDirectory() as tmp, patch('tools.resolve_player_ids.Client') as client:
            client.return_value.get.side_effect = APIError(429, 'HTTP 429')
            collect_profiles(Path(tmp), [], {}, rows, 'test-key', 0)
            self.assertTrue((Path(tmp) / 'official/identity/search_bios.json').exists())
            errors = read(Path(tmp) / 'official/identity/profile_collection_errors.json')
            self.assertEqual(errors[0]['provider_player_id'], 'sr:player:1')


if __name__ == '__main__':
    unittest.main()
