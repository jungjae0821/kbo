import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../data/app_data.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';

/// 교체 선수를 고르는 아래쪽 시트. 고르면 확인을 거쳐 선수 ID를 돌려준다.
/// 후보 순서: 투수는 시즌 투구 이닝, 타자는 타석 수가 많은 순 (주로 뛴 선수가 위).
Future<String?> pickSubstitute(
  BuildContext context, {
  required SubstitutionKind kind,
  required AppData data,
  required List<String> candidateIds,
  required String outPlayerName,
  required String title,
  bool confirmNoReturn = true,
}) async {
  final pitcher = kind == SubstitutionKind.pitcher;
  final candidates = [for (final id in candidateIds) data.player(id)]
    ..sort((a, b) => pitcher
        ? (b.outsPitched ?? 0).compareTo(a.outsPitched ?? 0)
        : (b.plateAppearances ?? 0).compareTo(a.plateAppearances ?? 0));

  final chosen = await showModalBottomSheet<PlayerCard>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.kbo.sheet,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => _SubstituteList(
      title: title,
      candidates: candidates,
      pitcher: pitcher,
    ),
  );
  if (chosen == null || !context.mounted) return null;
  // 경기 전 선발 고르기는 되돌릴 수 있으므로 확인을 묻지 않는다.
  if (!confirmNoReturn) return chosen.id;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(keepAll(pitcher
          ? '$outPlayerName 대신 ${withObject(chosen.name)} 올릴까요?'
          : '$outPlayerName 대신 ${withObject(chosen.name)} 낼까요?')),
      content: Text(keepAll('$outPlayerName 선수는 이 경기에 다시 나올 수 없습니다.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(pitcher ? '투수 교체' : '대타 내기'),
        ),
      ],
    ),
  );
  return ok == true ? chosen.id : null;
}

class _SubstituteList extends StatelessWidget {
  const _SubstituteList({required this.title, required this.candidates, required this.pitcher});

  final String title;
  final List<PlayerCard> candidates;
  final bool pitcher;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final base = text.bodyMedium!;
    final sub = base.copyWith(color: k.inkSub);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(keepAll(title), style: text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              keepAll(pitcher
                  ? '시즌 투구 이닝이 많은 순입니다. 기록이 적은 선수는 리그 평균에 가깝게 계산됩니다.'
                  : '시즌 타석이 많은 순입니다. 기록이 적은 선수는 리그 평균에 가깝게 계산됩니다.'),
              style: text.bodySmall?.copyWith(color: k.inkSub),
            ),
          ),
          Expanded(
            child: candidates.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(keepAll('남은 교체 선수가 없습니다.'), style: base),
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final p = candidates[i];
                      final line = pitcher
                          ? '평균자책 ${era(p.era)}, ${p.inningsPitched ?? '0'}이닝, ${p.wins ?? 0}승 ${p.losses ?? 0}패'
                              '${(p.saves ?? 0) > 0 ? ' ${p.saves}세이브' : ''}${(p.holds ?? 0) > 0 ? ' ${p.holds}홀드' : ''}'
                          : '타율 ${avg(p.battingAverage)}, 홈런 ${p.homeRuns ?? 0}, OPS ${avg(p.ops)}, ${p.plateAppearances ?? 0}타석';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, p),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: text.titleMedium),
                                  Text(line, style: sub),
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
