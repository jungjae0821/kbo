import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
import '../widgets/stat_tile.dart';
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
        return GroundLayout(
          title: '개인 기록',
          ground: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('누적 점수', style: text.bodyMedium?.copyWith(color: k.chalkSub)),
                Text('${r.totalPoints}점', style: text.displaySmall?.copyWith(color: k.chalk)),
                const SizedBox(height: 6),
                Text(
                  keepAll(r.decidedCount == 0
                      ? '승패가 갈린 경기가 아직 없습니다'
                      : '승패가 갈린 ${r.decidedCount}경기 중 ${r.hitCount}경기 적중'),
                  style: text.bodyMedium?.copyWith(color: k.chalk),
                ),
              ],
            ),
          ),
          sheet: SheetBody(
            children: [
              StatRow(tiles: [
                StatTile(label: '적중률', value: formatRate(r.hitRate)),
                StatTile(label: '예측', value: '${r.predictionCount}경기'),
                StatTile(label: '연속 적중', value: '${r.currentStreak}'),
                StatTile(label: '최다 연속', value: '${r.bestStreak}'),
              ]),
              const SheetHeading('최근 경기'),
              if (r.recent.isEmpty || data == null)
                Text(keepAll('끝낸 경기가 없습니다. 두 팀을 골라 첫 경기를 시작해 보세요.'), style: text.bodyMedium)
              else
                for (final g in r.recent.take(20))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${data.team(g.awayTeamId).shortName} ${g.awayScore} : ${g.homeScore} ${data.team(g.homeTeamId).shortName}',
                            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          g.isTie ? '무승부 0' : (g.isHit ? '적중 +${g.points}' : '빗나감 0'),
                          style: text.bodyMedium?.copyWith(color: g.isHit && !g.isTie ? k.accentText : k.inkSub),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 20),
              Text(
                keepAll('기록은 앱을 닫으면 사라집니다. 기기에 저장하는 기능은 다음 업데이트에서 추가됩니다.'),
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
