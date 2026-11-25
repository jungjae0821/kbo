import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';

/// 선수 한 명을 고르는 아래쪽 시트. 고른 선수 ID를 돌려준다.
Future<String?> pickPlayer(
  BuildContext context, {
  required String title,
  String? note,
  required List<String> candidateIds,
  required AppData data,
  required bool pitcher,
  String emptyMessage = '고를 수 있는 선수가 없습니다.',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PlayerList(
      title: title,
      note: note,
      candidates: [for (final id in candidateIds) data.player(id)],
      pitcher: pitcher,
      emptyMessage: emptyMessage,
    ),
  );
}

/// 투수 한 줄 요약: 시즌 평균자책, 선발 등판, 승패, 세이브·홀드.
String pitcherLine(PlayerCard p) {
  final parts = [
    '평균자책 ${era(p.era)}',
    if (p.pitcherStarts > 0) '선발 ${p.pitcherStarts}경기',
    '${p.wins ?? 0}승 ${p.losses ?? 0}패',
    if ((p.saves ?? 0) > 0) '${p.saves}세이브',
    if ((p.holds ?? 0) > 0) '${p.holds}홀드',
  ];
  return parts.join(', ');
}

/// 타자 한 줄 요약: 시즌 타율, 홈런, OPS, 타석.
String batterLine(PlayerCard p) =>
    '타율 ${avg(p.battingAverage)}, 홈런 ${p.homeRuns ?? 0}, OPS ${avg(p.ops)}, ${p.plateAppearances ?? 0}타석';

class _PlayerList extends StatelessWidget {
  const _PlayerList({
    required this.title,
    required this.note,
    required this.candidates,
    required this.pitcher,
    required this.emptyMessage,
  });

  final String title;
  final String? note;
  final List<PlayerCard> candidates;
  final bool pitcher;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(keepAll(title), style: text.titleLarge),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(keepAll(note!), style: text.bodySmall?.copyWith(color: k.inkSub)),
            ),
          Expanded(
            child: candidates.isEmpty
                ? Padding(padding: const EdgeInsets.all(20), child: Text(keepAll(emptyMessage), style: text.bodyMedium))
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final p = candidates[i];
                      return Material(
                        color: i.isEven ? k.stripe : Colors.transparent,
                        borderRadius: BorderRadius.circular(rowRadius),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(rowRadius),
                          onTap: () => Navigator.pop(context, p.id),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(p.name, style: text.titleMedium),
                                  Text(pitcher ? pitcherLine(p) : batterLine(p),
                                      style: text.bodySmall?.copyWith(color: k.inkSub)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
