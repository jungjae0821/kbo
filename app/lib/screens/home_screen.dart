import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
import '../widgets/stat_tile.dart';
import 'records_screen.dart';
import 'team_select_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.data, scope.records]),
      builder: (context, _) {
        final data = scope.data;
        final records = scope.records;
        final ready = data.status == DataStatus.ready;
        return GroundLayout(
          title: 'KBO 가상야구',
          ground: _HomeGround(data: data),
          sheet: SheetBody(
            children: [
              const SheetHeading('내 예측 기록', first: true),
              StatRow(
                tiles: [
                  StatTile(label: '누적 점수', value: '${records.totalPoints}'),
                  StatTile(label: '적중률', value: formatRate(records.hitRate)),
                  StatTile(label: '예측', value: '${records.predictionCount}경기'),
                ],
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
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecordsScreen()),
              ),
              child: const Text('개인 기록'),
            ),
          ),
        );
      },
    );
  }
}

class _HomeGround extends StatelessWidget {
  const _HomeGround({required this.data});
  final DataController data;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final Widget status = switch (data.status) {
      DataStatus.loading => Row(
          children: [
            const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('시즌 데이터를 확인하고 있습니다', style: text.bodyMedium?.copyWith(color: k.chalkSub)),
          ],
        ),
      DataStatus.ready => Text(
          keepAll('${data.data!.teams.length}개 팀, 선수 ${data.data!.playerCount}명의 기록이 준비됐습니다'),
          style: text.bodyMedium?.copyWith(color: k.chalkSub),
        ),
      DataStatus.failed => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(keepAll(data.error ?? ''), style: text.bodyMedium?.copyWith(color: k.chalk)),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: k.chalk,
                foregroundColor: k.grass,
              ),
              onPressed: data.load,
              child: const Text('다시 불러오기'),
            ),
          ],
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘의 승리 팀은?',
            style: text.displaySmall?.copyWith(color: k.chalk, fontSize: 38, height: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            keepAll('2026 KBO 정규시즌 기록으로 두 팀의 가상 경기를 치릅니다. 이길 팀을 맞히면 100점.'),
            style: text.bodyLarge?.copyWith(color: k.chalk),
          ),
          const SizedBox(height: 20),
          status,
        ],
      ),
    );
  }
}
