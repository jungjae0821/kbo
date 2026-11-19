import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/feed_layout.dart';
import '../widgets/record_sheet.dart';
import 'records_screen.dart';
import 'team_select_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// 홈에 보여 주는 최근 경기 수. 나머지는 개인 기록 화면에서 본다.
  static const _recentCount = 5;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.data, scope.records]),
      builder: (context, _) {
        final data = scope.data;
        final records = scope.records;
        final ready = data.status == DataStatus.ready;

        final Widget recent;
        if (data.status == DataStatus.loading) {
          recent = Bubble(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: k.inkSub)),
                const SizedBox(width: 10),
                Flexible(child: Text('시즌 기록을 읽는 중입니다', style: text.bodyMedium)),
              ],
            ),
          );
        } else if (data.status == DataStatus.failed) {
          recent = Bubble(
            stretch: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(keepAll(data.error ?? ''), style: text.bodyMedium),
                const SizedBox(height: 8),
                FilledButton(style: secondaryButtonStyle(context), onPressed: data.load, child: const Text('다시 불러오기')),
              ],
            ),
          );
        } else if (records.recent.isEmpty) {
          recent = Bubble(child: Text(keepAll('아직 끝낸 경기가 없습니다.'), style: text.bodyMedium));
        } else {
          recent = PredictionFeed(games: records.recent.take(_recentCount).toList(), data: data.data!);
        }

        return FeedScaffold(
          title: 'KBO 가상야구',
          body: FeedList(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text('2026 정규시즌 기록으로 치르는 가상 경기', style: text.bodySmall?.copyWith(color: k.inkSub)),
              ),
              PredictionSummary(records: records),
              const FeedHeading('지난 경기'),
              recent,
              const FeedHeading('새 경기'),
              Bubble(
                stretch: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(keepAll('두 팀을 고르면 전력을 비교하고 이길 팀을 예측합니다.'), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      keepAll('맞히면 ${RecordBook.pointsPerHit}점, 무승부는 0점이고 적중률에서 빠집니다.'),
                      style: text.bodySmall?.copyWith(color: k.inkSub),
                    ),
                    if (ready && data.notice != null) ...[
                      const SizedBox(height: 8),
                      Text(keepAll(data.notice!), style: text.bodySmall?.copyWith(color: k.inkSub)),
                      if (data.canRetry)
                        TextButton(onPressed: data.load, child: const Text('다시 불러오기')),
                    ],
                  ],
                ),
              ),
            ],
          ),
          dock: ActionRow(
            primary: FilledButton(
              onPressed: ready
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSelectScreen()))
                  : null,
              child: const Text('경기 만들기'),
            ),
            secondary: FilledButton(
              style: secondaryButtonStyle(context),
              onPressed: ready
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordsScreen()))
                  : null,
              child: const Text('개인 기록'),
            ),
          ),
        );
      },
    );
  }
}
