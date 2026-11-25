import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../state/box_score.dart';
import '../theme/kbo_theme.dart';

/// 이닝별 점수 + R(득점) H(안타) B(볼넷) 스코어보드. 결과 화면의 초점.
class Scoreboard extends StatelessWidget {
  const Scoreboard({
    super.key,
    required this.awayName,
    required this.homeName,
    required this.state,
    required this.box,
  });

  final String awayName;
  final String homeName;
  final GameState state;
  final BoxScore box;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final head = text.labelSmall!.copyWith(color: k.inkSub);
    final num = text.bodyMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final strong = text.titleMedium!.copyWith(color: k.accent);
    final innings = state.awayInnings.length < 9 ? 9 : state.awayInnings.length;

    String cell(List<int?> list, int i, bool away) {
      if (i >= list.length) return '';
      final v = list[i];
      if (v != null) return '$v';
      // 진행하지 않은 홈 공격(9회말 생략, 끝내기 뒤)은 X.
      return state.isFinished && !away ? 'X' : '';
    }

    Widget c(String s, TextStyle style) => SizedBox(height: 34, child: Center(child: Text(s, style: style, maxLines: 1)));

    TableRow row(String name, List<int?> list, int runs, int hits, int walks, bool away, {bool winner = false}) => TableRow(
          decoration: away ? BoxDecoration(color: k.stripe) : null,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                height: 34,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(name, style: text.titleSmall!.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.clip),
                ),
              ),
            ),
            for (var i = 0; i < innings; i++) c(cell(list, i, away), num),
            c('$runs', winner ? strong : text.titleMedium!),
            c('$hits', num),
            c('$walks', num),
          ],
        );

    final winnerId = state.isFinished && state.awayScore != state.homeScore
        ? (state.awayScore > state.homeScore ? box.away.teamId : box.home.teamId)
        : null;

    return Semantics(
      label: '스코어보드. $awayName ${state.awayScore}점 안타 ${box.away.hits} 볼넷 ${box.away.walks}, '
          '$homeName ${state.homeScore}점 안타 ${box.home.hits} 볼넷 ${box.home.walks}',
      excludeSemantics: true,
      child: Table(
        columnWidths: {
          0: const FixedColumnWidth(48),
          for (var i = 1; i <= innings; i++) i: const FlexColumnWidth(),
          innings + 1: const FixedColumnWidth(30),
          innings + 2: const FixedColumnWidth(28),
          innings + 3: const FixedColumnWidth(28),
        },
        children: [
          TableRow(children: [
            const SizedBox(height: 26),
            for (var i = 0; i < innings; i++) SizedBox(height: 26, child: Center(child: Text('${i + 1}', style: head))),
            SizedBox(height: 26, child: Center(child: Text('R', style: head))),
            SizedBox(height: 26, child: Center(child: Text('H', style: head))),
            SizedBox(height: 26, child: Center(child: Text('B', style: head))),
          ]),
          row(awayName, state.awayInnings, state.awayScore, box.away.hits, box.away.walks, true,
              winner: winnerId == box.away.teamId),
          row(homeName, state.homeInnings, state.homeScore, box.home.hits, box.home.walks, false,
              winner: winnerId == box.home.teamId),
        ],
      ),
    );
  }
}
