import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../state/labels.dart';
import '../theme/kbo_theme.dart';
import 'feed_layout.dart';

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

/// 이벤트가 일어난 이닝과 공수.
(int, bool) eventHalf(Object event) => event is PlateAppearanceLog
    ? (event.inning, event.isTop)
    : ((event as Substitution).inning, event.isTop);

/// 이닝 공수가 시작될 때 한 번만 나오는 제목 줄 (예: "3회말 삼성 공격"). 피드 가운데에 작게.
class HalfHeader extends StatelessWidget {
  const HalfHeader({super.key, required this.inning, required this.isTop, required this.attackingTeam});

  final int inning;
  final bool isTop;
  final String attackingTeam;

  /// 피드 높이 계산용: 위 [top] + 글자 한 줄 + 아래 [bottom].
  static const top = 8.0;
  static const bottom = 4.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: top, bottom: bottom),
      child: Semantics(
        header: true,
        child: Text(
          '${halfLabel(inning, isTop)} $attackingTeam 공격',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.kbo.inkSub),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// 타석과 교체를 일어난 순서대로 섞는다. 교체는 그 뒤 첫 타석 바로 앞에 온다.
List<Object> playEvents(List<PlateAppearanceLog> logs, List<Substitution> subs) {
  final events = <Object>[];
  var s = 0;
  for (final log in logs) {
    while (s < subs.length && subs[s].beforePlateAppearance <= log.number) {
      events.add(subs[s++]);
    }
    events.add(log);
  }
  events.addAll(subs.skip(s));
  return events;
}

/// 피드 메시지 한 칸의 세로 여백 (높이 계산용).
const playRowPadding = 7.0;

/// 교체 한 줄: "투수 김민수, 소형준 대신" / "대타 김지찬, 3번 박승규 대신".
class SubstitutionRow extends StatelessWidget {
  const SubstitutionRow({
    super.key,
    required this.sub,
    required this.inName,
    required this.outName,
    this.teamName,
    this.singleLine = false,
  });

  final Substitution sub;
  final String inName;
  final String outName;
  final String? teamName;

  /// 높이가 정해진 목록에서는 한 줄로 줄이고 넘치면 말줄임.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final pitcher = sub.kind == SubstitutionKind.pitcher;
    final team = teamName == null ? '' : '$teamName ';
    return Bubble(
      color: k.fill,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: playRowPadding),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: pitcher ? '$team투수 교체 ' : '$team대타 ', style: base.copyWith(color: k.inkSub)),
          TextSpan(text: inName, style: base.copyWith(fontWeight: FontWeight.w700)),
          TextSpan(text: pitcher ? ', $outName 대신' : ', ${sub.battingOrder}번 $outName 대신', style: base),
        ]),
        maxLines: singleLine ? 1 : null,
        overflow: singleLine ? TextOverflow.ellipsis : null,
      ),
    );
  }
}

/// 타석 한 칸: 타자와 결과, 그 뒤의 상황. 점수가 나면 강조 면.
class PlateRow extends StatelessWidget {
  const PlateRow({
    super.key,
    required this.log,
    required this.batterName,
    this.emphasize = false,
    this.singleLine = false,
  });

  final PlateAppearanceLog log;
  final String batterName;

  /// 가장 최근 타석이면 true.
  final bool emphasize;

  /// 높이가 정해진 목록에서는 한 줄로 줄이고 넘치면 말줄임.
  final bool singleLine;

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
      final b = basesLabel(log.transition.basesAfterPlay);
      after = b == '주자 없음' || b == '만루' ? b : '주자 $b';
    }
    return Bubble(
      soft: runs > 0,
      stretch: emphasize,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: playRowPadding),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: batterName, style: base.copyWith(fontWeight: FontWeight.w700)),
          TextSpan(text: ' ${outcomeLabel(log.outcome)}', style: base),
          TextSpan(
            text: ', $after',
            style: runs > 0
                ? base.copyWith(color: k.accentText, fontWeight: FontWeight.w700)
                : base.copyWith(color: k.inkSub),
          ),
        ]),
        maxLines: singleLine ? 1 : null,
        overflow: singleLine ? TextOverflow.ellipsis : null,
      ),
    );
  }
}
