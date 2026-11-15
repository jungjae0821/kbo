import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../state/labels.dart';
import '../theme/kbo_theme.dart';

/// 이닝별 점수표. 기록 시트 규칙대로 한 크기(14)로 쓰고 굵기·색으로만 구분한다.
class LineScore extends StatelessWidget {
  const LineScore({
    super.key,
    required this.awayName,
    required this.homeName,
    required this.state,
    required this.logs,
  });

  final String awayName;
  final String homeName;
  final GameState state;
  final List<PlateAppearanceLog> logs;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final head = base.copyWith(color: k.inkSub);
    final strong = base.copyWith(fontWeight: FontWeight.w700);
    final now = base.copyWith(color: k.accentText, fontWeight: FontWeight.w700);
    final columns = state.awayInnings.length < 9 ? 9 : state.awayInnings.length;
    final hits = <bool, int>{true: 0, false: 0};
    for (final log in logs) {
      if (isHit(log.outcome)) hits[log.isTop] = hits[log.isTop]! + 1;
    }

    String cell(List<int?> innings, int i, bool isAwayRow) {
      if (i >= innings.length) return '';
      final v = innings[i];
      if (v != null) return '$v';
      // 끝난 경기에서 진행하지 않은 홈 공격(9회말 생략)은 X로 표기한다.
      return state.isFinished && !isAwayRow ? 'X' : '';
    }

    bool isNow(int i, bool isAwayRow) =>
        !state.isFinished && i == state.inning - 1 && state.isTop == isAwayRow;

    Widget row(String name, List<int?> innings, int runs, int h, bool isAway, {bool header = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(name, style: header ? head : base, overflow: TextOverflow.ellipsis),
            ),
            for (var i = 0; i < columns; i++)
              Expanded(
                child: Text(
                  header ? '${i + 1}' : cell(innings, i, isAway),
                  textAlign: TextAlign.center,
                  style: header ? head : (isNow(i, isAway) ? now : base),
                ),
              ),
            SizedBox(
              width: 30,
              child: Text(header ? 'R' : '$runs', textAlign: TextAlign.center, style: header ? head : strong),
            ),
            SizedBox(
              width: 30,
              child: Text(header ? 'H' : '$h', textAlign: TextAlign.center, style: header ? head : base),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: '이닝별 점수. $awayName ${state.awayScore}점, $homeName ${state.homeScore}점',
      child: Column(
        children: [
          row('', const [], 0, 0, true, header: true),
          row(awayName, state.awayInnings, state.awayScore, hits[true]!, true),
          row(homeName, state.homeInnings, state.homeScore, hits[false]!, false),
        ],
      ),
    );
  }
}

/// 타석 한 줄: 번호, 타자와 결과, 그 뒤의 상황.
class PlateRow extends StatelessWidget {
  const PlateRow({
    super.key,
    required this.log,
    required this.batterName,
    this.emphasize = false,
  });

  final PlateAppearanceLog log;
  final String batterName;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final runs = log.transition.scored.length;
    final String after;
    if (runs > 0) {
      after = '$runs점';
    } else if (log.outcome == PlateOutcome.strikeout || log.outcome == PlateOutcome.otherOut) {
      after = '${log.transition.outsAfterPlay}아웃';
    } else {
      after = basesLabel(log.transition.basesAfterPlay);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text('${log.number}', style: base.copyWith(color: k.inkSub)),
          ),
          Expanded(
            child: Text(
              '$batterName ${outcomeLabel(log.outcome)}',
              style: emphasize ? base.copyWith(fontWeight: FontWeight.w700) : base,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            after,
            style: runs > 0
                ? base.copyWith(color: k.accentText, fontWeight: FontWeight.w700)
                : base.copyWith(color: k.inkSub),
          ),
        ],
      ),
    );
  }
}
