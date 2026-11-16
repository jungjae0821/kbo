import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
import '../widgets/line_score.dart';
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
        ? '무승부라 0점입니다. 적중률 계산에서 빠집니다.'
        : hit
            ? '예측 적중, ${RecordBook.pointsPerHit}점을 받았습니다.'
            : '예측이 빗나갔습니다. 0점입니다.';

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
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${endLabel(s.end!)}, ${s.plateAppearances}타석',
              style: text.bodyMedium?.copyWith(color: k.chalkSub),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _FinalSide(name: away.name, runs: s.awayScore, won: winnerId == away.id)),
                Text(':', style: text.displaySmall?.copyWith(color: k.chalkSub)),
                Expanded(child: _FinalSide(name: home.name, runs: s.homeScore, won: winnerId == home.id, end: true)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tie ? '무승부' : '${data.team(winnerId).name} 승리',
              style: text.headlineSmall?.copyWith(color: k.chalk),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              keepAll('내 예측 ${data.team(predictedWinnerId).shortName} 승리. $verdict'),
              style: text.bodyMedium?.copyWith(color: k.chalk),
              textAlign: TextAlign.center,
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

class _FinalSide extends StatelessWidget {
  const _FinalSide({required this.name, required this.runs, required this.won, this.end = false});

  final String name;
  final int runs;
  final bool won;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(name, style: text.bodyMedium?.copyWith(color: k.chalkSub), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('$runs', style: text.displaySmall?.copyWith(color: won ? k.chalk : k.chalkSub)),
      ],
    );
  }
}
