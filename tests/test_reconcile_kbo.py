import unittest

from tools.reconcile_kbo import Page, grid, merged_by_id, official_outs, table_rows, verify_filter


class OfficialTests(unittest.TestCase):
    def test_fractional_innings_are_outs(self):
        for value, expected in [('0', 0), ('1/3', 1), ('2/3', 2), ('6 2/3', 20), ('1292', 3876)]:
            self.assertEqual(official_outs(value), expected)
        with self.assertRaises(ValueError):
            official_outs('6.7')

    def test_season_and_regular_filter_are_required(self):
        page = Page('<select name="ctl$ddlSeason"><option selected value="2026">2026</option></select>'
                    '<select name="ctl$ddlSeries"><option selected value="7">한국시리즈</option></select>')
        with self.assertRaises(ValueError):
            verify_filter(page, 2026)
        page.form['ctl$ddlSeries'] = '0'
        verify_filter(page, 2026)

    def test_player_id_from_official_link_and_total_row_excluded(self):
        p = Page('<table class="tData01"><tr><th>선수명</th><th>H</th></tr>'
                 '<tr><td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=12345">김선수</a></td>'
                 '<td>10</td></tr><tr><td>합계</td><td>10</td></tr></table>')
        rows = table_rows(p)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['kbo_player_id'], '12345')

    def test_official_id_merge_rejects_conflicting_name(self):
        a = {'kbo_player_id': '1', '선수명': '김선수', '팀명': 'LG', 'source_file': 'a'}
        b = dict(a, 선수명='박선수', source_file='b')
        with self.assertRaises(ValueError):
            merged_by_id([a], [b])

    def test_grid_expands_total_column_span(self):
        self.assertEqual(grid({'rows': [{'row': [{'Text': 'TOTAL', 'ColSpan': '3'}, {'Text': '9'}]}]}),
                         [['TOTAL', '', '', '9']])


if __name__ == '__main__':
    unittest.main()
