import 'package:flutter/material.dart';

import '../theme/kbo_theme.dart';

/// 그라운드 위 이름표 한 개의 내용.
class FieldTag {
  const FieldTag(this.id, this.name, [this.detail]);
  final String id;
  final String name;
  final String? detail;
}

/// 시그니처: 흙 내야 위에 주자·타자·투수의 실제 이름이 서 있는 다이아몬드.
/// [runners]는 [1루, 2루, 3루].
class Diamond extends StatelessWidget {
  const Diamond({
    super.key,
    required this.runners,
    required this.outs,
    this.batter,
    this.pitcher,
    this.halfDiagonal = 100,
    this.compact = false,
    this.showOuts = true,
  });

  final List<FieldTag?> runners;
  final int outs;
  final FieldTag? batter;
  final FieldTag? pitcher;
  final double halfDiagonal;

  /// 작은 휴대폰용: 이름표를 한 줄로 줄이고 아래 여백을 줄인다.
  final bool compact;

  /// 아웃 표시를 다이아몬드 안에 그릴지. 작은 화면에서는 점수판 쪽에 둔다.
  final bool showOuts;

  /// 이름표 높이: 이름(titleSmall 15sp, 행간 1.35)과 기록(bodySmall 12sp, 행간 1.3), 글자 크기 설정 반영.
  static double tagHeight(TextScaler scaler, {required bool compact}) => compact
      ? scaler.scale(15) * 1.35 + 4
      : scaler.scale(15) * 1.35 + scaler.scale(12) * 1.3 + 6;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final d = halfDiagonal;
    final below = compact ? 13.0 : 18.0;
    // 맨 아래 타자 이름표가 칸 밖으로 나가지 않게 높이를 이름표 실제 높이로 잡는다.
    final height = (d + 22) + d + below + tagHeight(MediaQuery.textScalerOf(context), compact: compact) + 2;
    final reduce = MediaQuery.of(context).disableAnimations;
    final dur = reduce ? Duration.zero : motion;

    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, box) {
        final cx = box.maxWidth / 2;
        final cy = d + 22;
        final second = Offset(cx, cy - d);
        final first = Offset(cx + d, cy);
        final third = Offset(cx - d, cy);
        final home = Offset(cx, cy + d);

        Widget base(Offset at, bool on) => Positioned(
              left: at.dx - 11,
              top: at.dy - 11,
              child: Transform.rotate(
                angle: 0.785398,
                child: AnimatedContainer(
                  duration: dur,
                  curve: motionCurve,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on ? k.chalk : k.chalk.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );

        // [above]이면 이름표 아래 끝을 anchor에 맞춘다 (베이스 위쪽에 놓을 때).
        Widget tag(FieldTag? t, Offset anchor, {Alignment align = Alignment.topCenter, bool above = false}) {
          return Positioned(
            left: anchor.dx,
            top: anchor.dy,
            child: FractionalTranslation(
              translation: Offset(-(align.x + 1) / 2, above ? -1 : 0),
              child: AnimatedSwitcher(
                duration: dur,
                switchInCurve: motionCurve,
                child: t == null
                    ? const SizedBox.shrink()
                    : _NameTag(key: ValueKey(t.id), tag: t, inline: compact),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _InfieldPainter(
                  center: Offset(cx, cy),
                  halfDiagonal: d,
                  clay: k.clay,
                  infieldGrass: k.grassDeep,
                  mound: k.clayDeep,
                ),
              ),
            ),
            base(second, runners[1] != null),
            base(first, runners[0] != null),
            base(third, runners[2] != null),
            base(home, true),
            tag(runners[1], second + const Offset(18, -14), align: Alignment.topLeft),
            // 1·3루 주자 이름표는 베이스 위쪽(바깥)에 둔다. 아래쪽은 가운데 투수 이름표와
            // 같은 높이라 만루일 때 서로 겹친다.
            tag(runners[0], first + Offset(0, -below), above: true),
            tag(runners[2], third + Offset(0, -below), above: true),
            tag(pitcher, Offset(cx, cy + (compact ? 10 : 14))),
            tag(batter, home + Offset(0, below)),
            if (showOuts)
              Positioned(
                left: 16,
                bottom: 4,
                child: OutsBoard(outs: outs),
              ),
          ],
        );
      }),
    );
  }
}

class _NameTag extends StatelessWidget {
  const _NameTag({super.key, required this.tag, this.inline = false});
  final FieldTag tag;

  /// 이름과 기록을 한 줄에 (작은 화면).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: k.grassDeep,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inline ? 6 : 8, vertical: inline ? 2 : 3),
        child: Flex(
          direction: inline ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: inline ? CrossAxisAlignment.baseline : CrossAxisAlignment.center,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              tag.name,
              style: text.titleSmall?.copyWith(
                color: k.chalk,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (tag.detail != null && inline) const SizedBox(width: 4),
            if (tag.detail != null)
              Text(
                tag.detail!,
                style: text.bodySmall?.copyWith(color: k.chalkSub, height: 1.3),
              ),
          ],
        ),
      ),
    );
  }
}

/// 아웃 카운트: 어두운 면 위 빨간 동그라미 3개와 "N아웃".
class OutsBoard extends StatelessWidget {
  const OutsBoard({super.key, required this.outs});
  final int outs;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final reduce = MediaQuery.of(context).disableAnimations;
    // 빨간 아웃 표시는 잔디 위에서 잘 안 보여 전광판처럼 어두운 면 위에 둔다.
    return Semantics(
      label: '$outs아웃',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: k.board, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                AnimatedContainer(
                  duration: reduce ? Duration.zero : motion,
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: i < outs ? k.outRed : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: k.outRed, width: 2),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                '$outs아웃',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: k.chalkSub, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfieldPainter extends CustomPainter {
  _InfieldPainter({
    required this.center,
    required this.halfDiagonal,
    required this.clay,
    required this.infieldGrass,
    required this.mound,
  });

  final Offset center;
  final double halfDiagonal;
  final Color clay;
  final Color infieldGrass;
  final Color mound;

  Path _diamond(double r) => Path()
    ..moveTo(center.dx, center.dy - r)
    ..lineTo(center.dx + r, center.dy)
    ..lineTo(center.dx, center.dy + r)
    ..lineTo(center.dx - r, center.dy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final outer = halfDiagonal + 26;
    final inner = halfDiagonal - 26;
    final clayPaint = Paint()
      ..color = clay
      ..style = PaintingStyle.fill;
    // 모서리를 살짝 둥글게: 같은 색 굵은 선으로 덮어 꼭짓점을 누그러뜨린다.
    canvas.drawPath(_diamond(outer - 6), clayPaint);
    canvas.drawPath(
      _diamond(outer - 6),
      Paint()
        ..color = clay
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(_diamond(inner), Paint()..color = infieldGrass);
    canvas.drawCircle(center, 9, Paint()..color = mound);
  }

  @override
  bool shouldRepaint(_InfieldPainter old) =>
      old.center != center ||
      old.halfDiagonal != halfDiagonal ||
      old.clay != clay;
}
