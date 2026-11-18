import 'package:flutter/material.dart';

import '../theme/kbo_theme.dart';

/// 휴대폰 기준 내용 폭. 태블릿·가로 화면에서는 가운데 이 폭으로 묶는다.
const contentMaxWidth = 600.0;

/// 모든 화면의 뼈대 (DESIGN.md 4절): 위 상태 띠, 가운데 피드, 아래 버튼.
class FeedScaffold extends StatelessWidget {
  const FeedScaffold({
    super.key,
    this.title,
    this.leading,
    this.appBarActions,
    this.header,
    required this.body,
    this.dock,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? appBarActions;

  /// 스크롤되지 않는 위쪽 영역 (상태 띠, 고르는 줄).
  final Widget? header;
  final Widget body;

  /// 맨 아래 고정 영역 (감독 줄, 버튼 줄).
  final Widget? dock;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 앱 바도 내용 폭 안에 둔다. 넓은 화면에서 제목만 왼쪽 끝에 떨어지지 않게.
                if (title != null || leading != null)
                  AppBar(
                    primary: false,
                    title: title == null ? null : Text(title!),
                    leading: leading,
                    actions: appBarActions,
                  ),
                if (header != null) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: header),
                Expanded(child: body),
                if (dock != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: dock),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 스크롤되는 피드 목록.
class FeedList extends StatelessWidget {
  const FeedList({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding ?? const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: children,
    );
  }
}

/// 피드 안 구역 제목. 가운데에 두되, 이닝 공수 제목(작은 회색)보다 한 단계 크고 진하게 써서 구분한다.
class FeedHeading extends StatelessWidget {
  const FeedHeading(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 18, bottom: 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// 피드의 메시지 한 칸. [soft]는 점수·적중처럼 한 단계 강조한 면.
class Bubble extends StatelessWidget {
  const Bubble({
    super.key,
    required this.child,
    this.soft = false,
    this.stretch = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    this.onTap,
    this.color,
  });

  final Widget child;
  final bool soft;

  /// 폭을 다 채울지. 기본은 내용 폭(최대 88%)으로 왼쪽에 붙는다.
  final bool stretch;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final box = Material(
      color: color ?? (soft ? k.soft : k.surface),
      borderRadius: BorderRadius.circular(bubbleRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (stretch) return box;
    return LayoutBuilder(
      // heightFactor 1: 높이는 내용만큼. 없으면 남은 높이를 다 차지해 세로 가운데에 선다.
      builder: (context, c) => Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth * 0.88), child: box),
      ),
    );
  }
}

/// 위쪽 상태 띠: 원정 점수, 가운데 이닝과 아웃, 홈 점수.
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.awayName,
    required this.awayScore,
    required this.homeName,
    required this.homeScore,
    required this.center,
    this.outs,
    this.semanticsLabel,
  });

  final String awayName;
  final int awayScore;
  final String homeName;
  final int homeScore;
  final String center;

  /// null이면 아웃 점을 그리지 않는다 (경기 종료 등).
  final int? outs;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final name = text.bodySmall!.copyWith(color: k.statusSub);
    final score = text.displaySmall!.copyWith(color: k.onStatus);

    Widget side(String n, int s, bool end) => Row(
          mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (end) ...[Text('$s', style: score), const SizedBox(width: 6)],
            Flexible(child: Text(n, style: name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (!end) ...[const SizedBox(width: 6), Text('$s', style: score)],
          ],
        );

    return Semantics(
      liveRegion: true,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: DecoratedBox(
        decoration: BoxDecoration(color: k.status, borderRadius: BorderRadius.circular(statusRadius)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(child: side(awayName, awayScore, false)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(center, style: text.titleSmall?.copyWith(color: k.onStatus, fontWeight: FontWeight.w700)),
                    if (outs != null) ...[const SizedBox(height: 4), OutDots(outs: outs!)],
                  ],
                ),
              ),
              Expanded(child: side(homeName, homeScore, true)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 아웃 점 세 개. 상태 띠 위에서만 쓴다.
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
            width: 8,
            height: 8,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
            decoration: BoxDecoration(color: i < outs ? k.outRed : k.statusOff, shape: BoxShape.circle),
          ),
      ],
    );
  }
}

/// 작은 베이스 그림. [bases]는 [1루, 2루, 3루] 주자 유무.
class BasesMini extends StatelessWidget {
  const BasesMini({super.key, required this.bases, this.size = 44});

  final List<bool> bases;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final bag = size * 0.3;
    final reduce = MediaQuery.of(context).disableAnimations;
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
              decoration: BoxDecoration(
                color: bases[i] ? k.accent : k.baseOff,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
    final mid = (size - bag) / 2;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          base(1, mid, size * 0.06),
          base(0, size - bag - size * 0.06, mid),
          base(2, size * 0.06, mid),
        ],
      ),
    );
  }
}

/// 버튼 줄: 주 버튼은 남은 폭을 채우고, 보조 버튼은 내용 폭.
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: primary),
        if (secondary != null) ...[const SizedBox(width: 8), secondary!],
      ],
    );
  }
}
