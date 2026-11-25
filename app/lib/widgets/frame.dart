import 'package:flutter/material.dart';

import '../state/labels.dart';
import '../theme/kbo_theme.dart';

/// 휴대폰 기준 내용 폭. 태블릿·가로 화면에서는 가운데 이 폭으로 묶는다.
const contentMaxWidth = 600.0;

/// 모든 화면의 뼈대: 위 남색 자막 띠, 가운데 내용, 아래 고정 버튼 줄 (DESIGN.md 1·4절).
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.band, required this.body, this.dock, this.overlap});

  /// 위쪽 남색 띠 안의 내용.
  final Widget band;
  final Widget body;
  final Widget? dock;

  /// 띠 경계에 걸쳐 띄우는 카드 (이어하기 등). 없으면 띠와 내용이 바로 붙는다.
  final Widget? overlap;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    return Scaffold(
      backgroundColor: k.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: k.band,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 16, overlap == null ? 14 : 38),
                    child: DefaultTextStyle.merge(style: TextStyle(color: k.onBand), child: band),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (overlap != null)
                        Transform.translate(
                          offset: const Offset(0, -26),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: overlap),
                        ),
                      Expanded(
                        child: Transform.translate(
                          offset: Offset(0, overlap == null ? 0 : -18),
                          child: body,
                        ),
                      ),
                      if (dock != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: dock),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 띠 안 제목 줄: 뒤로 가기(있으면) + 제목 + 오른쪽 보조 글자.
class BandTitle extends StatelessWidget {
  const BandTitle({super.key, required this.title, this.back = false, this.onBack, this.trailing});

  final String title;
  final bool back;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(color: k.onBand);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          if (back)
            IconButton(
              tooltip: '뒤로',
              color: k.onBand,
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 내용 안 구역 제목.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 6), this.trailing});

  final String text;
  final EdgeInsets padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 흰(다크: 남색) 카드 한 장. 그림자는 띠에 걸친 카드에만 쓴다 (DESIGN.md 5절).
class LiftedCard extends StatelessWidget {
  const LiftedCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(14, 8, 8, 8)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? k.stripe : k.bg,
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : const Color(0xFF141846)).withValues(alpha: dark ? 0.4 : 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 줄무늬 면 한 칸 (안내, 빈 상태, 오류).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.color, this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 10)});

  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color ?? context.kbo.stripe, borderRadius: BorderRadius.circular(cardRadius)),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 안내 문장 (원인과 다음 행동). [action]이 있으면 오른쪽에 버튼.
class NoticePanel extends StatelessWidget {
  const NoticePanel({super.key, required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: EdgeInsets.fromLTRB(14, 8, action == null ? 14 : 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(keepAll(message), style: text.bodySmall)),
          ?action,
        ],
      ),
    );
  }
}

/// 원정·홈 점수와 이닝·아웃을 담은 띠 내용 (경기·결과 화면).
class ScoreBand extends StatelessWidget {
  const ScoreBand({
    super.key,
    required this.awayName,
    required this.awayScore,
    required this.homeName,
    required this.homeScore,
    required this.center,
    this.outs,
    this.bases,
  });

  final String awayName;
  final int awayScore;
  final String homeName;
  final int homeScore;
  final String center;

  /// null이면 아웃 점을 그리지 않는다 (경기 종료).
  final int? outs;
  final List<bool>? bases;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final name = text.bodyMedium!.copyWith(color: k.bandSub);
    final score = text.displaySmall!.copyWith(color: k.onBand);

    Widget side(String n, int s, bool end) => Column(
          crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(n, style: name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('$s', style: score),
          ],
        );

    return Semantics(
      liveRegion: true,
      label: '$center${outs == null ? '' : ', $outs아웃'}, $awayName $awayScore점, $homeName $homeScore점',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Expanded(child: side(awayName, awayScore, false)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(center, style: text.titleSmall!.copyWith(color: k.onBand)),
                if (outs != null) ...[const SizedBox(height: 6), OutDots(outs: outs!)],
                if (bases != null) ...[const SizedBox(height: 4), BasesMini(bases: bases!, onBand: true)],
              ],
            ),
            Expanded(child: side(homeName, homeScore, true)),
          ],
        ),
      ),
    );
  }
}

/// 아웃 점 세 개. 띠 위에서만 쓴다.
class OutDots extends StatelessWidget {
  const OutDots({super.key, required this.outs});
  final int outs;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 9,
            height: 9,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 5),
            decoration: BoxDecoration(color: i < outs ? k.outRed : k.bandOff, shape: BoxShape.circle),
          ),
      ],
    );
  }
}

/// 작은 베이스 그림. [bases]는 [1루, 2루, 3루] 주자 유무.
class BasesMini extends StatelessWidget {
  const BasesMini({super.key, required this.bases, this.size = 34, this.onBand = false});

  final List<bool> bases;
  final double size;
  final bool onBand;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final bag = size * 0.32;
    final reduce = MediaQuery.of(context).disableAnimations;
    final on = onBand ? k.onBand : k.accent;
    final off = onBand ? k.bandOff : k.baseOff;
    Widget base(int i, double left, double top) => Positioned(
          left: left,
          top: top,
          child: Transform.rotate(
            angle: 0.785398,
            child: AnimatedContainer(
              duration: reduce ? Duration.zero : motion,
              curve: motionCurve,
              width: bag,
              height: bag,
              decoration: BoxDecoration(color: bases[i] ? on : off, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        );
    final mid = (size - bag) / 2;
    return SizedBox(
      width: size,
      height: size * 0.62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          base(1, mid, 0),
          base(0, size - bag - size * 0.04, size * 0.24),
          base(2, size * 0.04, size * 0.24),
        ],
      ),
    );
  }
}

/// 버튼 줄: 주 버튼은 남은 폭, 보조 버튼은 내용 폭.
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (secondary != null) ...[secondary!, const SizedBox(width: 8)],
        Expanded(child: primary),
      ],
    );
  }
}
