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
  });

  final List<FieldTag?> runners;
  final int outs;
  final FieldTag? batter;
  final FieldTag? pitcher;
  final double halfDiagonal;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final d = halfDiagonal;
    final height = d * 2 + 76;
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

        Widget tag(FieldTag? t, Offset anchor, {Alignment align = Alignment.topCenter}) {
          return Positioned(
            left: anchor.dx,
            top: anchor.dy,
            child: FractionalTranslation(
              translation: Offset(-(align.x + 1) / 2, 0),
              child: AnimatedSwitcher(
                duration: dur,
                switchInCurve: motionCurve,
                child: t == null
                    ? const SizedBox.shrink()
                    : _NameTag(key: ValueKey(t.id), tag: t),
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
            tag(runners[0], first + const Offset(0, 18)),
            tag(runners[2], third + const Offset(0, 18)),
            tag(pitcher, Offset(cx, cy + 14)),
            tag(batter, home + const Offset(0, 18)),
            Positioned(
              left: 16,
              bottom: 4,
              child: _Outs(outs: outs),
            ),
          ],
        );
      }),
    );
  }
}

class _NameTag extends StatelessWidget {
  const _NameTag({super.key, required this.tag});
  final FieldTag tag;

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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tag.name,
              style: text.titleSmall?.copyWith(
                color: k.chalk,
                fontWeight: FontWeight.w700,
              ),
            ),
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

class _Outs extends StatelessWidget {
  const _Outs({required this.outs});
  final int outs;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    return Semantics(
      label: '$outs아웃',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : motion,
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: i < outs ? k.chalk : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: k.chalk, width: 2),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '$outs아웃',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: k.chalkSub),
          ),
        ],
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
