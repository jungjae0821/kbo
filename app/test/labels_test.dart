import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/data/app_data.dart';
import 'package:kbo_app/state/labels.dart';
import 'package:kbo_engine/kbo_engine.dart';

void main() {
  test('아웃 중 생긴 상황은 병살타·희생플라이·진루타로 보인다', () {
    final data = AppData.parse(File('assets/data/season_dataset.json').readAsStringSync());
    final ids = data.season.teams.keys.toList();
    final seen = <PlayNote, String>{};
    for (var seed = 0; seed < 50 && seen.length < PlayNote.values.length; seed++) {
      final engine = GameEngine(
        dataset: data.season,
        awayTeamId: ids[0],
        homeTeamId: ids[1],
        seed: 1000003 * (seed + 1),
        gameId: 'labels-$seed',
      )..playToEnd();
      for (final log in engine.logs) {
        final note = log.transition.note;
        if (note != null) seen[note] = playLabel(log);
      }
    }
    expect(seen, {
      PlayNote.doublePlay: '병살타',
      PlayNote.runScoredOnOut: '희생플라이',
      PlayNote.runnerAdvancedOnOut: '진루타',
    });
  });
}
