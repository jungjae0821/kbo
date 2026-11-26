import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/data/app_data.dart';
import 'package:kbo_app/state/auto_bullpen.dart';
import 'package:kbo_app/state/box_score.dart';
import 'package:kbo_engine/kbo_engine.dart';

void main() {
  final data = AppData.parse(File('assets/data/season_dataset.json').readAsStringSync());
  final ids = data.season.teams.keys.toList();

  GameEngine play(int seed, String away, String home, String auto) {
    final g = GameEngine(dataset: data.season, awayTeamId: away, homeTeamId: home, seed: seed);
    while (!g.state.isFinished) {
      autoPitchingChange(g, data, auto);
      g.step();
    }
    return g;
  }

  test('상대 팀만 자동 교체하고, 선발은 6회 전후에 내려가며, 이어하기로 똑같이 되살아난다', () {
    var games = 0, starterInnings = 0, relievers = 0;
    for (var seed = 1; seed <= 120; seed++) {
      final away = ids[seed % 10], home = ids[(seed * 7 + 3) % 10];
      if (away == home) continue;
      final g = play(seed, away, home, home);
      games++;
      expect(g.substitutions.every((s) => s.teamId == home && s.kind == SubstitutionKind.pitcher), isTrue);
      final box = BoxScore.from(g);
      starterInnings += box.home.pitchers.first.outs;
      relievers += box.home.pitchers.length - 1;
      // 9회 이후 세이브 상황이면 세이브가 가장 많은 투수 쪽으로 간다: 마무리는 구원투수.
      if (box.home.pitchers.length > 1) {
        expect(data.player(box.home.pitchers.last.playerId).pitcherStarts < 10 ||
            g.pitcherCandidates(home).every((id) => data.player(id).pitcherStarts >= 10), isTrue);
      }
      final restored = GameEngine.restore(data.season, jsonDecode(jsonEncode(g.toCheckpoint())) as Map<String, dynamic>);
      expect(restored.toJson(), g.toJson());
    }
    final avgStarterInnings = starterInnings / games / 3;
    final avgRelievers = relievers / games;
    expect(avgStarterInnings, inInclusiveRange(4.5, 7.2), reason: '선발 평균 $avgStarterInnings이닝');
    expect(avgRelievers, inInclusiveRange(1.0, 4.5), reason: '경기당 구원 $avgRelievers명');
  });

  test('공격 중이거나 첫 타자 전에는 바꾸지 않는다', () {
    final g = GameEngine(dataset: data.season, awayTeamId: ids[0], homeTeamId: ids[1], seed: 3);
    expect(autoPitchingChange(g, data, ids[1]), isNull); // 첫 타자 전
    expect(autoPitchingChange(g, data, ids[0]), isNull); // 원정은 1회초 공격 중
  });

  test('정한 불펜 운용: 계투 순서대로 오르고, 세이브 상황에는 마무리가 오른다', () {
    var closerUsed = 0, games = 0;
    for (var seed = 1; seed <= 80; seed++) {
      final away = ids[seed % 10], home = ids[(seed * 3 + 1) % 10];
      if (away == home) continue;
      final g = GameEngine(dataset: data.season, awayTeamId: away, homeTeamId: home, seed: seed);
      final plans = {
        for (final t in [away, home]) t: BullpenPlan.suggested(data, t, g.startingPitcherFor(t)),
      };
      while (!g.state.isFinished) {
        for (final t in [away, home]) {
          autoPitchingChange(g, data, t, plan: plans[t]);
        }
        g.step();
      }
      games++;
      for (final t in [away, home]) {
        final plan = plans[t]!;
        final ins = [for (final s in g.substitutions) if (s.teamId == t) s.inPlayerId];
        // 마무리를 뺀 등판 순서는 계투 순서의 앞부분과 같다 (순서를 다 쓰기 전까지).
        final middle = [for (final id in ins) if (id != plan.closer) id];
        final n = middle.length < plan.order.length ? middle.length : plan.order.length;
        expect(middle.take(n).toList(), plan.order.take(n).toList(), reason: 'seed $seed $t');
        if (plan.closer != null && ins.contains(plan.closer)) closerUsed++;
      }
      final restored = GameEngine.restore(data.season, jsonDecode(jsonEncode(g.toCheckpoint())) as Map<String, dynamic>);
      expect(restored.toJson(), g.toJson());
    }
    expect(games, greaterThan(50));
    expect(closerUsed, greaterThan(0));
  });

  test('불펜 운용 편집: 다른 자리에 있던 투수를 고르면 자리를 맞바꾸고, 저장 형식으로 되살린다', () {
    final t = ids.first;
    final starter = data.season.lineups[t]!.pitcherId;
    final plan = BullpenPlan.suggested(data, t, starter);
    expect(plan.order.length, BullpenPlan.size);
    expect(plan.order.contains(starter), isFalse);
    expect(plan.closer, isNotNull);
    expect(plan.order.contains(plan.closer), isFalse);

    final swapped = plan.withOrder(0, plan.order[2]);
    expect(swapped.order[0], plan.order[2]);
    expect(swapped.order[2], plan.order[0]);
    final closerSwap = plan.withCloser(plan.order[1]);
    expect(closerSwap.closer, plan.order[1]);
    expect(closerSwap.order[1], plan.closer);
    final toOrder = plan.withOrder(3, plan.closer!);
    expect(toOrder.order[3], plan.closer);
    expect(toOrder.closer, plan.order[3]);

    final back = BullpenPlan.fromJson(jsonDecode(jsonEncode(swapped.toJson())));
    expect(back!.sameAs(swapped), isTrue);
    expect(BullpenPlan.fromJson({'order': [1, 2]}), isNull);
  });
}
