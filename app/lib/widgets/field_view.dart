import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/kbo_theme.dart';

/// 문자중계식 그라운드: 다이아몬드 위에 주자 이름, 마운드에 투수, 홈에 타자, 옆에 아웃.
/// 경기 진행 화면에서 문자 기록과 나눠 위쪽에 크게 둔다.
class FieldView extends StatelessWidget {
  const FieldView({
    super.key,
    required this.runners,
    required this.pitcherName,
    required this.pitcherDetail,
    required this.batterName,
    required this.batterDetail,
    required this.outs,
    required this.situation,
  });

  /// [1루, 2루, 3루] 주자 이름. 비었으면 null.
  final List<String?> runners;
  final String pitcherName;
  final String pitcherDetail;
  final String batterName;
  final String batterDetail;
  final int outs;

  /// "5회초 KT 공격"처럼 지금 상황.
  final String situation;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final on = [for (final r in runners) r != null];
    final baseNames = ['1루', '2루', '3루'];
    final runnerText = [
      for (var i = 0; i < 3; i++)
        if (runners[i] != null) '${baseNames[i]} ${runners[i]}',
    ];
    return Semantics(
      liveRegion: true,
      label: '$situation, $outs아웃, ${runnerText.isEmpty ? '주자 없음' : runnerText.join(', ')}. '
          '투수 $pitcherName, 타자 $batterName',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        // 다이아몬드: 홈을 아래 가운데에 두고 정사각형을 45도 돌린 모양.
        final half = math.min(w * 0.30, (h - 46) / 2);
        final cx = w / 2, cy = 10 + half;
        final home = Offset(cx, cy + half), first = Offset(cx + half, cy), second = Offset(cx, cy - half), third = Offset(cx - half, cy);
        final bases = [first, second, third];
        const bag = 20.0;

        Widget label(String s, {required TextStyle style, TextAlign align = TextAlign.center}) =>
            Text(s, style: style, textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis);

        final runnerStyle = text.titleSmall!.copyWith(color: k.band, fontSize: 14);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _DiamondPainter(k, home, bases, on, bag))),
            // 주자 이름: 1루는 오른쪽, 3루는 왼쪽, 2루는 위.
            if (runners[0] != null)
              Positioned(
                left: first.dx + bag / 2 + 6,
                right: 0,
                top: first.dy - 10,
                child: label(runners[0]!, style: runnerStyle, align: TextAlign.left),
              ),
            if (runners[2] != null)
              Positioned(
                left: 0,
                right: w - third.dx + bag / 2 + 6,
                top: third.dy - 10,
                child: label(runners[2]!, style: runnerStyle, align: TextAlign.right),
              ),
            if (runners[1] != null)
              Positioned(
                left: cx - 80,
                width: 160,
                top: second.dy - bag / 2 - 22,
                child: label(runners[1]!, style: runnerStyle),
              ),
            // 마운드의 투수.
            Positioned(
              left: cx - w * 0.36,
              width: w * 0.72,
              top: cy - 18,
              child: Column(children: [
                label('투수 $pitcherName', style: text.titleSmall!.copyWith(fontSize: 14)),
                label(pitcherDetail, style: text.bodySmall!.copyWith(color: k.inkSub, fontSize: 12)),
              ]),
            ),
            // 홈의 타자.
            Positioned(
              left: 0,
              right: 0,
              top: home.dy + bag / 2 + 2,
              child: Column(children: [
                label(batterName, style: text.titleMedium!),
                label(batterDetail, style: text.bodySmall!.copyWith(color: k.inkSub, fontSize: 12)),
              ]),
            ),
            // 왼쪽 위: 상황과 아웃.
            Positioned(
              left: 0,
              top: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(situation, style: text.labelMedium!.copyWith(color: k.inkSub)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('아웃', style: text.labelMedium!.copyWith(color: k.inkSub)),
                    const SizedBox(width: 6),
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 11,
                        height: 11,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(color: i < outs ? k.outRed : k.baseOff.withValues(alpha: 0.35), shape: BoxShape.circle),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _DiamondPainter extends CustomPainter {
  _DiamondPainter(this.k, this.home, this.bases, this.on, this.bag);

  final KboColors k;
  final Offset home;
  final List<Offset> bases;
  final List<bool> on;
  final double bag;

  @override
  void paint(Canvas canvas, Size size) {
    // 베이스 라인.
    final line = Paint()
      ..color = k.baseOff.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(home.dx, home.dy)
      ..lineTo(bases[0].dx, bases[0].dy)
      ..lineTo(bases[1].dx, bases[1].dy)
      ..lineTo(bases[2].dx, bases[2].dy)
      ..close();
    canvas.drawPath(path, line);

    // 베이스: 주자가 있으면 남색, 비었으면 흰 면에 회색 테두리 한 겹.
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(bases[i].dx, bases[i].dy);
      canvas.rotate(math.pi / 4);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: bag, height: bag), const Radius.circular(3));
      if (on[i]) {
        canvas.drawRRect(r, Paint()..color = k.band);
      } else {
        canvas.drawRRect(r, Paint()..color = k.bg);
        canvas.drawRRect(r, Paint()
          ..color = k.baseOff
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
      canvas.restore();
    }
    // 홈 플레이트 (오각형).
    const s = 9.0;
    final plate = Path()
      ..moveTo(home.dx - s, home.dy - s)
      ..lineTo(home.dx + s, home.dy - s)
      ..lineTo(home.dx + s, home.dy)
      ..lineTo(home.dx, home.dy + s)
      ..lineTo(home.dx - s, home.dy)
      ..close();
    canvas.drawPath(plate, Paint()..color = k.ink);
  }

  @override
  bool shouldRepaint(_DiamondPainter old) => old.on.toString() != on.toString() || old.home != home;
}
