import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../state/labels.dart';
import '../theme/kbo_theme.dart';

/// 이벤트가 일어난 이닝과 공수.
(int, bool) eventHalf(Object event) => event is PlateAppearanceLog
    ? (event.inning, event.isTop)
    : ((event as Substitution).inning, event.isTop);

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

/// 기록 한 줄의 높이 (글자 한 줄 + 위아래 여백). 남은 높이에 들어가는 줄 수를 셀 때 쓴다.
const playRowPadding = 7.0;

/// 이닝 공수가 시작될 때 한 번만 나오는 제목 줄 (예: "3회말 삼성 공격").
class HalfHeader extends StatelessWidget {
  const HalfHeader({super.key, required this.inning, required this.isTop, required this.attackingTeam});

  final int inning;
  final bool isTop;
  final String attackingTeam;

  static const top = 8.0;
  static const bottom = 2.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: top, bottom: bottom, left: 4),
      child: Semantics(
        header: true,
        child: Text(
          '${halfLabel(inning, isTop)} $attackingTeam 공격',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: context.kbo.inkSub),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// 타석 한 줄: 타자와 결과, 그 뒤의 상황. 점수가 나면 강조 면.
class PlateRow extends StatelessWidget {
  const PlateRow({super.key, required this.log, required this.batterName, this.latest = false});

  final PlateAppearanceLog log;
  final String batterName;

  /// 가장 최근 타석이면 true (굵게).
  final bool latest;

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
    return _Row(
      color: runs > 0 ? k.accentSoft : null,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: batterName, style: base.copyWith(fontWeight: FontWeight.w700)),
          TextSpan(text: ' ${playLabel(log)}', style: latest ? base.copyWith(fontWeight: FontWeight.w700) : base),
          TextSpan(
            text: ', $after',
            style: runs > 0
                ? base.copyWith(fontWeight: FontWeight.w700)
                : base.copyWith(color: k.inkSub),
          ),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 교체 한 줄: "투수 교체 김민수, 소형준 대신" / "대타 김지찬, 3번 박승규 대신".
class SubstitutionRow extends StatelessWidget {
  const SubstitutionRow({super.key, required this.sub, required this.inName, required this.outName, this.teamName});

  final Substitution sub;
  final String inName;
  final String outName;
  final String? teamName;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final pitcher = sub.kind == SubstitutionKind.pitcher;
    final team = teamName == null ? '' : '$teamName ';
    return _Row(
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: pitcher ? '$team투수 교체 ' : '$team대타 ', style: base.copyWith(color: k.inkSub)),
          TextSpan(text: inName, style: base.copyWith(fontWeight: FontWeight.w700)),
          TextSpan(text: pitcher ? ', $outName 대신' : ', ${sub.battingOrder}번 $outName 대신', style: base),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: playRowPadding), child: child),
    );
  }
}
