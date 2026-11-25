import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/box_score.dart';
import '../state/game_setup.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/frame.dart';
import '../widgets/saved_game_actions.dart';
import '../widgets/scoreboard.dart';
import 'box_score_screen.dart';

/// 경기 결과: 스코어보드로 간략하게 → 승리·패전·세이브·홀드 투수 → 예측 결과.
/// 상세보기는 타자·투수 기록, 다시하기는 준비 화면(직전 설정), 처음으로는 메인 (초안 확정 구조 4).
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.engine, required this.predictedWinnerId});

  final GameEngine engine;
  final String predictedWinnerId;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data.data!;
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final s = engine.state;
    final away = data.team(engine.awayTeamId);
    final home = data.team(engine.homeTeamId);
    final winnerId = engine.winnerTeamId;
    final tie = winnerId == null;
    final hit = winnerId == predictedWinnerId;
    final box = BoxScore.from(engine);

    void toHome() => Navigator.of(context).popUntil((r) => r.isFirst);
    void again() {
      Navigator.of(context).popUntil((r) => r.isFirst);
      startNewGame(context, setup: GameSetup.from(engine));
    }

    final verdict = tie ? '무승부, 0점 (적중률에서 제외)' : (hit ? '적중, +${RecordBook.pointsPerHit}점' : '빗나감, 0점');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) toHome();
      },
      child: AppFrame(
        band: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BandTitle(
              title: '경기 결과',
              trailing: Text(endLabel(s.end!), style: text.bodySmall!.copyWith(color: k.bandSub)),
            ),
            ScoreBand(
              awayName: away.shortName,
              awayScore: s.awayScore,
              homeName: home.shortName,
              homeScore: s.homeScore,
              center: tie ? '무승부' : '${data.team(winnerId).shortName} 승리',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          children: [
            Scoreboard(awayName: away.shortName, homeName: home.shortName, state: s, box: box),
            const SizedBox(height: 14),
            _Decisions(box: box, data: data),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Panel(
                color: hit && !tie ? k.accentSoft : k.stripe,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '내 예측 ${data.team(predictedWinnerId).shortName} 승리, ', style: text.bodyMedium!.copyWith(color: k.inkSub)),
                  TextSpan(
                    text: verdict,
                    style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
                  ),
                ])),
              ),
            ),
          ],
        ),
        dock: Row(
          children: [
            TextButton(onPressed: toHome, child: const Text('처음으로')),
            const SizedBox(width: 4),
            FilledButton(
              style: bandButtonStyle(context, height: 56),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BoxScoreScreen(engine: engine))),
              child: const Text('상세보기'),
            ),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: again, child: const Text('다시하기'))),
          ],
        ),
      ),
    );
  }
}

/// 승리·패전·세이브·홀드 투수. 기록지처럼 두 줄로. 없으면 "-".
class _Decisions extends StatelessWidget {
  const _Decisions({required this.box, required this.data});

  final BoxScore box;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    String name(String? id) => id == null ? '-' : data.player(id).name;
    final rows = [
      ('승리', name(box.winningPitcherId)),
      ('패전', name(box.losingPitcherId)),
      ('세이브', name(box.savePitcherId)),
      ('홀드', box.holdPitcherIds.isEmpty ? '-' : box.holdPitcherIds.map(name).join(', ')),
    ];
    Widget cell((String, String) r) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text(r.$1, style: text.bodySmall!.copyWith(color: k.inkSub))),
                Expanded(child: Text(r.$2, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        );
    return Semantics(
      label: '투수 기록. ${rows.map((r) => '${r.$1} ${r.$2 == '-' ? '없음' : r.$2}').join(', ')}',
      excludeSemantics: true,
      child: Column(
        children: [
          Row(children: [cell(rows[0]), cell(rows[1])]),
          Row(children: [cell(rows[2]), cell(rows[3])]),
        ],
      ),
    );
  }
}
