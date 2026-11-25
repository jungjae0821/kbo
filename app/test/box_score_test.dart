import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/state/box_score.dart';
import 'package:kbo_engine/kbo_engine.dart';

void main() {
  final season = SeasonDataset.fromJson(
    jsonDecode(File('assets/data/season_dataset.json').readAsStringSync()) as Map<String, dynamic>,
  );
  final ids = season.teams.keys.toList();

  test('기록표 합계가 경기 결과와 맞고, 승패 투수는 이긴 팀·진 팀에서 나온다', () {
    for (var seed = 1; seed <= 200; seed++) {
      final away = ids[seed % ids.length], home = ids[(seed * 3 + 1) % ids.length];
      if (away == home) continue;
      final game = GameEngine(dataset: season, awayTeamId: away, homeTeamId: home, seed: seed);
      // 홈 팀은 5회에 투수를 바꿔 구원 판정도 지나가게 한다.
      while (!game.state.isFinished) {
        if (game.state.inning == 5 && game.state.isTop && game.canSubstitutePitcher(home) &&
            game.substitutions.isEmpty) {
          game.substitutePitcher(home, game.pitcherCandidates(home).first);
        }
        game.step();
      }
      final box = BoxScore.from(game);
      final s = game.state;
      int runs(TeamBox t) => t.batters.fold(0, (a, b) => a + b.runs);
      int allowed(TeamBox t) => t.pitchers.fold(0, (a, p) => a + p.runs);
      expect(runs(box.away), s.awayScore, reason: 'seed $seed');
      expect(runs(box.home), s.homeScore, reason: 'seed $seed');
      expect(allowed(box.home), s.awayScore, reason: 'seed $seed');
      expect(allowed(box.away), s.homeScore, reason: 'seed $seed');
      final pa = box.away.batters.fold(0, (a, b) => a + b.plateAppearances) +
          box.home.batters.fold(0, (a, b) => a + b.plateAppearances);
      expect(pa, s.plateAppearances);
      final hits = game.logs.where((l) => const [
            PlateOutcome.single, PlateOutcome.doubleHit, PlateOutcome.triple, PlateOutcome.homeRun,
          ].contains(l.outcome)).length;
      expect(box.away.hits + box.home.hits, hits);

      final winner = game.winnerTeamId;
      if (winner == null) {
        expect(box.winningPitcherId, isNull);
        expect(box.losingPitcherId, isNull);
      } else {
        final w = winner == away ? box.away : box.home;
        final l = winner == away ? box.home : box.away;
        expect(w.pitchers.map((p) => p.playerId), contains(box.winningPitcherId), reason: 'seed $seed');
        expect(l.pitchers.map((p) => p.playerId), contains(box.losingPitcherId), reason: 'seed $seed');
        if (box.savePitcherId != null) {
          expect(box.savePitcherId, isNot(box.winningPitcherId));
          expect(w.pitchers.last.playerId, box.savePitcherId);
        }
        for (final h in box.holdPitcherIds) {
          expect(w.pitchers.map((p) => p.playerId), contains(h));
        }
      }
    }
  });

  test('이닝 표기와 대타 줄', () {
    final p = PitcherLine('x')..outs = 16;
    expect(p.innings, '5 1/3');
    expect((PitcherLine('y')..outs = 2).innings, '2/3');
    expect((PitcherLine('z')..outs = 27).innings, '9');

    final game = GameEngine(dataset: season, awayTeamId: ids[0], homeTeamId: ids[1], seed: 5);
    game.step();
    game.pinchHit(ids[0], game.pinchHitterCandidates(ids[0]).first);
    game.playToEnd();
    final box = BoxScore.from(game);
    expect(box.away.batters.length, 10);
    expect(box.away.batters[2].pinchHitter, isTrue);
    expect(box.away.batters[2].order, 2);
  });
}
