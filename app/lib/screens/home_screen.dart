import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
import '../widgets/record_sheet.dart';
import 'records_screen.dart';
import 'team_select_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// 홈 기록지에 보여 주는 최근 경기 수. 나머지는 개인 기록 화면에서 본다.
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
          recent = Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: k.inkSub),
              ),
              const SizedBox(width: 10),
              Text('시즌 기록을 읽는 중입니다', style: text.bodyMedium?.copyWith(color: k.inkSub)),
            ],
          );
        } else if (data.status == DataStatus.failed) {
          recent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(keepAll(data.error ?? ''), style: text.bodyMedium),
              const SizedBox(height: 8),
              FilledButton(
                style: secondaryButtonStyle(context),
                onPressed: data.load,
                child: const Text('다시 불러오기'),
              ),
            ],
          );
        } else if (records.recent.isEmpty) {
          recent = Text(
            keepAll('아직 끝낸 경기가 없습니다. 두 팀을 고르고 이길 팀을 예측해 보세요.'),
            style: text.bodyMedium,
          );
        } else {
          recent = PredictionLedger(
            games: records.recent.take(_recentCount).toList(),
            data: data.data!,
          );
        }

        return GroundLayout(
          title: 'KBO 가상야구',
          ground: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            child: PredictionStatLine(records: records),
          ),
          sheet: SheetBody(
            children: [
              const SheetHeading('최근 예측', first: true),
              recent,
              const SizedBox(height: 24),
              Text(
                keepAll('2026 정규시즌 기록으로 치르는 가상 경기입니다. '
                    '이긴 팀을 맞히면 ${RecordBook.pointsPerHit}점, 무승부는 0점이고 적중률에서 빠집니다.'),
                style: text.bodySmall?.copyWith(color: k.inkSub),
              ),
            ],
          ),
          actions: ActionRow(
            primary: FilledButton(
              onPressed: ready
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TeamSelectScreen()),
                      )
                  : null,
              child: const Text('경기 시작'),
            ),
            secondary: FilledButton(
              style: secondaryButtonStyle(context),
              onPressed: ready
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RecordsScreen()),
                      )
                  : null,
              child: const Text('개인 기록'),
            ),
          ),
        );
      },
    );
  }
}
