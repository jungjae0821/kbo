import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../data/data_controller.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/frame.dart';
import '../widgets/saved_game_actions.dart';

/// 개인 기록: 띠에 누적 점수와 적중률, 아래 경기별 기록.
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
        final missed = r.decidedCount - r.hitCount;
        final ties = r.predictionCount - r.decidedCount;
        final watched = r.gameCount - r.predictionCount;
        final rate = r.hitRate == null ? '-' : '${(r.hitRate! * 100).round()}%';
        return AppFrame(
          band: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BandTitle(title: '개인 기록', back: true),
              Semantics(
                label: '누적 ${r.totalPoints}점, ${r.gameCount}경기 중 예측 ${r.predictionCount}경기, 적중 ${r.hitCount}, 빗나감 $missed, 무승부 $ties, '
                    '적중률 ${r.hitRate == null ? '없음' : rate}, 지금 ${r.currentStreak}경기 연속 적중, 최다 ${r.bestStreak}경기',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text.rich(
                    TextSpan(
                      style: text.bodyMedium!.copyWith(color: k.bandSub, height: 1.6),
                      children: [
                        TextSpan(text: '누적 ', style: text.bodyMedium!.copyWith(color: k.bandSub)),
                        TextSpan(text: '${r.totalPoints}점', style: text.headlineSmall!.copyWith(color: k.onBand)),
                        TextSpan(
                          text: '\n${r.predictionCount}경기 예측${watched > 0 ? ', 돌려보기 $watched경기' : ''}, 적중률 $rate. '
                              '지금 ${r.currentStreak}경기 연속 적중, 최다 ${r.bestStreak}경기.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            children: [
              if (r.notice != null) ...[NoticePanel(message: r.notice!), const SizedBox(height: 8)],
              SectionTitle('경기별 기록', padding: const EdgeInsets.fromLTRB(8, 0, 8, 4)),
              if (r.recent.isEmpty || data == null)
                NoticePanel(message: '끝낸 경기가 없습니다.')
              else
                for (final (i, g) in r.recent.indexed) _GameRow(game: g, striped: i.isEven, data: data),
            ],
          ),
          dock: FilledButton(
            onPressed: ready ? () => startNewGame(context) : null,
            child: const Text('시뮬레이션 시작'),
          ),
        );
      },
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game, required this.striped, required this.data});

  final GameRecord game;
  final bool striped;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final g = game;
    final away = data.team(g.awayTeamId).shortName;
    final home = data.team(g.homeTeamId).shortName;
    final pick = g.predictedWinnerId == null ? null : data.team(g.predictedWinnerId!).shortName;
    final date = '${g.finishedAt.month}.${g.finishedAt.day}';
    final hit = g.isHit && !g.isTie;
    final winner = g.isTie ? '무승부' : '${data.team(g.winnerTeamId!).shortName} 승';
    final result = pick == null ? winner : (g.isTie ? '무승부 0점' : (hit ? '적중 +${g.points}점' : '빗나감 0점'));
    return Semantics(
      label: '$date, $away ${g.awayScore} 대 ${g.homeScore} $home, ${pick == null ? '예측 없이 돌려보기' : '내 예측 $pick'}, $result',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hit ? k.accentSoft : (striped ? k.stripe : null),
        ),
        child: Row(
          children: [
            SizedBox(width: 44, child: Text(date, style: text.bodySmall!.copyWith(color: k.inkSub))),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$away ${g.awayScore} : ${g.homeScore} $home', style: text.titleSmall),
                  Text(pick == null ? '예측 없이 돌려보기' : '예측 $pick', style: text.bodySmall!.copyWith(color: k.inkSub)),
                ],
              ),
            ),
            Text(result, style: text.bodyMedium!.copyWith(color: hit ? k.ink : k.inkSub, fontWeight: hit ? FontWeight.w700 : null)),
          ],
        ),
      ),
    );
  }
}
