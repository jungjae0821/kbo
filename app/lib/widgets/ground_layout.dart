import 'package:flutter/material.dart';

import '../theme/kbo_theme.dart';

/// 모든 화면의 두 층: 위는 잔디 그라운드, 아래는 기록 시트.
/// 넓은 화면(840dp 이상)에서는 그라운드를 왼쪽, 시트를 오른쪽에 둔다.
class GroundLayout extends StatelessWidget {
  const GroundLayout({
    super.key,
    required this.title,
    required this.ground,
    required this.sheet,
    this.actions,
    this.leading,
    this.appBarActions,
  });

  final String title;
  final Widget ground;
  final Widget sheet;

  /// 시트 맨 아래에 고정되는 버튼 줄.
  final Widget? actions;
  final Widget? leading;
  final List<Widget>? appBarActions;

  static const _sheetRadius = Radius.circular(22);

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final appBar = AppBar(
      title: Text(title),
      leading: leading,
      actions: appBarActions,
    );

    Widget sheetPanel(BorderRadius radius) => ClipRRect(
          borderRadius: radius,
          child: ColoredBox(
            color: k.sheet,
            child: Column(
              children: [
                Expanded(child: sheet),
                if (actions != null)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: actions,
                    ),
                  ),
              ],
            ),
          ),
        );

    return Scaffold(
      backgroundColor: k.grass,
      appBar: appBar,
      body: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= 840) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // 스크롤 뷰 안에서는 높이가 열려 있어 그라운드가 내용 높이만 차지하고 세로 가운데에 선다.
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: ground,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 480,
                  child: sheetPanel(
                    const BorderRadius.only(topLeft: _sheetRadius),
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ground,
              Expanded(
                child: sheetPanel(
                  const BorderRadius.vertical(top: _sheetRadius),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 시트 안 내용 폭을 휴대폰 기준으로 묶는다 (태블릿 세로에서 줄이 너무 길어지지 않게).
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 20, 16, 16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// 시트 안 구역 제목. 위쪽 여백을 아래보다 크게 둔다.
class SheetHeading extends StatelessWidget {
  const SheetHeading(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 28, bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Row(
          children: [
            Expanded(child: primary),
            if (secondary != null) ...[const SizedBox(width: 8), secondary!],
          ],
        ),
      ),
    );
  }
}
