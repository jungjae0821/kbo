import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
import '../widgets/record_sheet.dart';
import 'team_select_screen.dart';

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
        final streak = r.predictionCount == 0
            ? '연속 적중 기록이 아직 없습니다'
            : '지금 ${r.currentStreak}경기 연속 적중, 최다 ${r.bestStreak}경기';
        return GroundLayout(
          title: '개인 기록',
          ground: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PredictionStatLine(records: r),
                const SizedBox(height: 14),
                Text(keepAll(streak), style: text.bodyMedium?.copyWith(color: k.chalk)),
              ],
            ),
          ),
          sheet: SheetBody(
            children: [
              const SheetHeading('경기별 기록', first: true),
              if (r.recent.isEmpty || data == null)
                Text(keepAll('끝낸 경기가 없습니다. 두 팀을 골라 첫 경기를 시작해 보세요.'), style: text.bodyMedium)
              else
                PredictionLedger(games: r.recent, data: data, showDate: true),
              const SizedBox(height: 24),
              Text(
                keepAll('앱을 닫으면 이 기록은 지워집니다.'),
                style: text.bodySmall?.copyWith(color: k.inkSub),
              ),
            ],
          ),
          actions: ActionRow(
            primary: FilledButton(
              onPressed: ready
                  ? () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const TeamSelectScreen()),
                      )
                  : null,
              child: const Text('경기 시작'),
            ),
          ),
        );
      },
    );
  }
}
