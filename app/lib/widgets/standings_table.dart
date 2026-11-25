import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';

/// 정규시즌 순위표: 열 10개를 한 화면 폭에 넣는다 (초안 판정 17·18).
/// 승률 순, 게임차는 1위 기준 ((1위 승 - 승) + (패 - 1위 패)) / 2.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.teams, this.rowHeight = 36});

  final List<TeamSummary> teams;
  final double rowHeight;

  /// 열 이름과 폭 비율. 합 100.
  static const _columns = [
    ('순위', 8.5),
    ('팀', 13.0),
    ('승률', 13.0),
    ('게임차', 10.5),
    ('경기', 8.5),
    ('승', 8.5),
    ('패', 8.5),
    ('무', 6.5),
    ('타율', 12.0),
    ('평균\n자책', 10.5),
  ];

  static List<TeamSummary> ranked(List<TeamSummary> teams) =>
      [...teams]..sort((a, b) => b.winRate.compareTo(a.winRate));

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final head = text.labelSmall!.copyWith(color: k.inkSub, height: 1.15);
    final num = text.bodySmall!.copyWith(fontSize: 13, height: 1.2, fontFeatures: const [FontFeature.tabularFigures()]);
    final rows = ranked(teams);
    final top = rows.first;

    String gb(TeamSummary t) {
      final v = ((top.wins - t.wins) + (t.losses - top.losses)) / 2;
      return v.toStringAsFixed(1);
    }

    Widget cell(String s, TextStyle style, {Alignment align = Alignment.center}) => Align(
          alignment: align,
          child: Text(s, style: style, maxLines: s.contains('\n') ? 2 : 1, overflow: TextOverflow.clip, textAlign: TextAlign.center),
        );

    final widths = {for (final (i, c) in _columns.indexed) i: FractionColumnWidth(c.$2 / 100)};

    return Semantics(
      label: '정규시즌 순위표, ${rows.length}개 팀',
      child: Table(
        columnWidths: widths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final (i, c) in _columns.indexed)
                SizedBox(
                  height: 32,
                  child: cell(c.$1, head,
                      align: i == 1 ? Alignment.centerLeft : Alignment.center),
                ),
            ],
          ),
          for (final (i, t) in rows.indexed)
            TableRow(
              decoration: i.isEven ? BoxDecoration(color: k.stripe) : null,
              children: [
                SizedBox(height: rowHeight, child: cell('${i + 1}', text.labelMedium!.copyWith(color: k.inkSub, fontSize: 13))),
                Semantics(
                  label: '${i + 1}위 ${t.name}, 승률 ${t.winRate.toStringAsFixed(3)}, ${t.wins}승 ${t.losses}패 ${t.ties}무',
                  excludeSemantics: true,
                  child: cell(t.shortName, text.titleSmall!.copyWith(fontSize: 14), align: Alignment.centerLeft),
                ),
                cell(t.winRate.toStringAsFixed(3), text.titleSmall!.copyWith(fontSize: 13.5, color: k.accent)),
                cell(gb(t), num),
                cell('${t.games}', num),
                cell('${t.wins}', num),
                cell('${t.losses}', num),
                cell('${t.ties}', num),
                cell(t.battingAverage == null ? '-' : t.battingAverage!.toStringAsFixed(3), num),
                cell(era(t.era), num),
              ],
            ),
        ],
      ),
    );
  }
}
