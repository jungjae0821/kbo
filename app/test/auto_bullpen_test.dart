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
}
