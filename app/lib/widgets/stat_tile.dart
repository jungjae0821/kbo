import 'package:flutter/material.dart';

import '../theme/kbo_theme.dart';

/// 적중률 표기. 승패가 갈린 경기가 없으면 "—".
String formatRate(double? rate) => rate == null ? '—' : '${(rate * 100).round()}%';

/// 시트 위 기록 한 칸: 값이 위, 이름이 아래.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: text.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: text.bodySmall?.copyWith(color: k.inkSub)),
        ],
      ),
    );
  }
}

/// 기록 칸을 한 면 위에 같은 폭으로 나란히 둔다.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.kbo.sheetRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [for (final t in tiles) Expanded(child: t)],
        ),
      ),
    );
  }
}
