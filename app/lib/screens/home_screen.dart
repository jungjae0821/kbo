import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/feed_layout.dart';
import '../widgets/home_board.dart';
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

        final Widget season;
        if (data.status == DataStatus.loading) {
          season = Bubble(
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
          season = Bubble(
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
        } else {
          season = SeasonStandings(teams: data.data!.teams);
        }

        final year = ready && data.data!.year.isNotEmpty ? data.data!.year : '2026';

        return FeedScaffold(
          title: 'KBO 가상야구',
          body: FeedList(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text('$year 정규시즌 기록으로 치르는 가상 경기', style: text.bodySmall?.copyWith(color: k.inkSub)),
              ),
              PredictionBoard(records: records),
              if (ready && records.recent.isNotEmpty) ...[
                const FeedHeading('지난 경기'),
                PredictionFeed(games: records.recent.take(_recentCount).toList(), data: data.data!),
              ],
              if (ready && data.notice != null) ...[
                const SizedBox(height: 12),
                Bubble(
                  stretch: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(keepAll(data.notice!), style: text.bodySmall?.copyWith(color: k.inkSub)),
                      if (data.canRetry) TextButton(onPressed: data.load, child: const Text('다시 불러오기')),
                    ],
                  ),
                ),
              ],
              FeedHeading('$year 정규시즌 순위'),
              season,
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
