import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
import '../widgets/line_score.dart';
import '../widgets/record_sheet.dart';
import 'records_screen.dart';
import 'team_select_screen.dart';

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
    final logs = engine.logs;

    final verdict = tie
        ? '무승부 0점 (적중률에서 제외)'
        : hit
            ? '적중 +${RecordBook.pointsPerHit}점'
            : '빗나감 0점';

    // 이닝 공수별로 타석과 교체를 일어난 순서대로 묶는다.
    final subs = engine.substitutions;
    final halves = <(int, bool), List<Object>>{};
    for (final event in playEvents(logs, subs)) {
      final key = event is PlateAppearanceLog
          ? (event.inning, event.isTop)
          : ((event as Substitution).inning, event.isTop);
      halves.putIfAbsent(key, () => []).add(event);
    }

    void again() {
      Navigator.of(context).popUntil((r) => r.isFirst);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSelectScreen()));
    }

    return GroundLayout(
      title: '경기 결과',
      leading: IconButton(
        tooltip: '홈으로',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
      ground: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              keepAll('${tie ? '무승부' : '${data.team(winnerId).name} 승리'}, ${endLabel(s.end!)} (${s.plateAppearances}타석)'),
              style: text.bodyMedium?.copyWith(color: k.chalk),
            ),
            const SizedBox(height: 4),
            GroundTeamRow(
              side: '원정',
              name: away.name,
              score: s.awayScore,
              muted: !tie && winnerId != away.id,
              semanticsLabel: '원정 ${away.name} ${s.awayScore}점',
            ),
            GroundTeamRow(
              side: '홈',
              name: home.name,
              score: s.homeScore,
              muted: !tie && winnerId != home.id,
              semanticsLabel: '홈 ${home.name} ${s.homeScore}점',
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '내 예측 ${data.team(predictedWinnerId).shortName} 승리, ',
                    style: text.bodyMedium?.copyWith(color: k.chalkSub),
                  ),
                  TextSpan(
                    text: verdict,
                    style: text.bodyMedium?.copyWith(color: k.chalk, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      sheet: SheetBody(
        children: [
          const SheetHeading('이닝별 점수', first: true),
          LineScore(awayName: away.shortName, homeName: home.shortName, state: s, logs: logs),
          const SheetHeading('타석 기록'),
          for (final entry in halves.entries) ...[
            HalfHeader(
              inning: entry.key.$1,
              isTop: entry.key.$2,
              attackingTeam: entry.key.$2 ? away.shortName : home.shortName,
            ),
            for (final event in entry.value)
              if (event is PlateAppearanceLog)
                PlateRow(log: event, batterName: data.player(event.batterId).name)
              else if (event is Substitution)
                SubstitutionRow(
                  sub: event,
                  inName: data.player(event.inPlayerId).name,
                  outName: data.player(event.outPlayerId).name,
                  teamName: data.team(event.teamId).shortName,
                ),
          ],
          const SizedBox(height: 12),
          Text(
            keepAll(subs.isEmpty
                ? '가상 경기 결과입니다. 경기 번호 ${engine.seed}로 같은 대진을 다시 하면 같은 경기가 나옵니다.'
                : '가상 경기 결과입니다. 경기 번호 ${engine.seed}로 같은 대진을 다시 하고 같은 시점에 같은 교체를 하면 같은 경기가 나옵니다.'),
            style: text.bodySmall?.copyWith(color: k.inkSub),
          ),
        ],
      ),
      actions: ActionRow(
        primary: FilledButton(onPressed: again, child: const Text('다시 경기')),
        secondary: FilledButton(
          style: secondaryButtonStyle(context),
          onPressed: () {
            Navigator.of(context).popUntil((r) => r.isFirst);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordsScreen()));
          },
          child: const Text('개인 기록'),
        ),
      ),
    );
  }
}
