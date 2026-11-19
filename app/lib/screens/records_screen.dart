import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';
import '../widgets/feed_layout.dart';
import '../widgets/record_sheet.dart';
import '../widgets/saved_game_card.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: scope.records,
      builder: (context, _) {
        final r = scope.records;
        final data = scope.data.data;
        final ready = scope.data.status == DataStatus.ready;
        return FeedScaffold(
          title: '개인 기록',
          body: FeedList(
            children: [
              PredictionSummary(records: r, showStreak: true),
              const FeedHeading('경기별 기록'),
              if (r.recent.isEmpty || data == null)
                Bubble(child: Text(keepAll('끝낸 경기가 없습니다. 두 팀을 골라 첫 경기를 만들어 보세요.'), style: text.bodyMedium))
              else
                PredictionFeed(games: r.recent, data: data, showDate: true),
              const SizedBox(height: 16),
              Text(
                keepAll(r.store == null ? '앱을 닫으면 이 기록은 지워집니다.' : '기록은 이 기기에 저장되어 앱을 다시 열어도 남습니다.'),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: k.inkSub),
              ),
            ],
          ),
          dock: ActionRow(
            primary: FilledButton(
              onPressed: ready ? () => startNewGame(context, replace: true) : null,
              child: const Text('경기 만들기'),
            ),
          ),
        );
      },
    );
  }
}
