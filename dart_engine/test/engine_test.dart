// Dependency-free test runner: dart run test/engine_test.dart
import 'dart:convert';
import 'dart:io';

import '../lib/kbo_engine.dart';

int passed = 0;
final failures = <String>[];
final checks = <Map<String, dynamic>>[];

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void equal(Object? actual, Object? expected) {
  check(jsonEncode(actual) == jsonEncode(expected), '$actual != $expected');
}

void throws(void Function() action) {
  var didThrow = false;
  try {
    action();
  } catch (_) {
    didThrow = true;
  }
  check(didThrow, 'Expected an exception');
}

void test(String name, void Function() action) {
  try {
    action();
    passed++;
    checks.add({'name': name, 'passed': true});
    stdout.writeln('PASS $name');
  } catch (error, stack) {
    failures.add(name);
    checks.add({'name': name, 'passed': false, 'error': error.toString()});
    stderr.writeln('FAIL $name: $error\n$stack');
  }
}

Map<String, dynamic> profile(List<double> values) => {
      for (final event in PlateOutcome.values) event.key: values[event.index],
    };

GameState late({
  int inning = 9,
  bool top = false,
  int outs = 0,
  int away = 0,
  int home = 0,
  List<String?> bases = const [null, null, null],
}) =>
    GameState(
      inning: inning,
      isTop: top,
      outs: outs,
      awayScore: away,
      homeScore: home,
      bases: bases,
      awayInnings: [away, ...List<int>.filled(inning - 1, 0)],
      homeInnings: [home, ...List<int?>.filled(inning - 2, 0), top ? null : 0],
    );

void main(List<String> args) {
  final datasetPath = args.isEmpty
      ? '../kbo_data/kbo_2026_138278/app/season_dataset.json'
      : args.first;
  final raw =
      jsonDecode(File(datasetPath).readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> copy() =>
      jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
  final dataset = SeasonDataset.fromJson(raw);

  test('real dataset: 10 teams, 591 players, 10 validated lineups', () {
    equal(
      [dataset.teams.length, dataset.players.length, dataset.lineups.length],
      [10, 591, 10],
    );
  });
  test('reject unsupported schema and rule versions', () {
    for (final key in ['schema_version', 'rules']) {
      final value = copy();
      if (key == 'rules') {
        value['rules']['version'] = '2.0.0';
      } else {
        value[key] = '2.0.0';
      }
      throws(() => SeasonDataset.fromJson(value));
    }
  });
  test('reject changed combination rule or event order', () {
    final a = copy();
    a['rules']['matchup'] = 'multiply';
    throws(() => SeasonDataset.fromJson(a));
    final b = copy();
    b['rules']['events'] = (b['rules']['events'] as List).reversed.toList();
    throws(() => SeasonDataset.fromJson(b));
  });
  test('reject duplicate player IDs and unknown player references', () {
    final a = copy();
    a['players'].add(a['players'][0]);
    throws(() => SeasonDataset.fromJson(a));
    final b = copy();
    b['lineups'][0]['starting_pitcher_id'] = 'unknown';
    throws(() => SeasonDataset.fromJson(b));
  });
  test(
    'reject wrong affiliation, duplicate batters, missing slots and positions',
    () {
      for (var mutation = 0; mutation < 4; mutation++) {
        final value = copy();
        final order = value['lineups'][0]['batting_order'] as List;
        if (mutation == 0) {
          final id = order[0]['player_id'];
          (value['players'] as List).firstWhere(
            (p) => p['player_id'] == id,
          )['assigned_team_id'] = 'unknown';
        } else if (mutation == 1) {
          order[1]['player_id'] = order[0]['player_id'];
        } else if (mutation == 2) {
          order.removeLast();
        } else {
          order[1]['position_code'] = order[0]['position_code'];
        }
        throws(() => SeasonDataset.fromJson(value));
      }
    },
  );
  test('reject zero sample and fallback profiles for selected players', () {
    for (final zero in [true, false]) {
      final value = copy();
      final id = value['lineups'][0]['starting_pitcher_id'];
      final p = (value['players'] as List).firstWhere(
        (p) => p['player_id'] == id,
      )['engine_profiles']['pitching'];
      if (zero) {
        p['sample_size'] = 0;
      } else {
        p['fallback_reason'] = 'missing_required_fields';
      }
      throws(() => SeasonDataset.fromJson(value));
    }
  });
  test(
      'reject missing, negative, nonfinite, all-zero and unnormalized probabilities',
      () {
    for (final invalid in [-0.1, double.nan, double.infinity, '0.5', null, 2]) {
      final value = profile([0, 0, 0, 0, 0, 0, 1]);
      value['strikeout'] = invalid;
      throws(() => EventProbabilities.fromJson(value));
    }
    throws(() => EventProbabilities.fromJson(profile(List.filled(7, 0))));
    throws(() => EventProbabilities.fromJson(profile(List.filled(7, 0.5))));
  });
  test('matchup uses arithmetic mean without applying a second prior', () {
    final a = EventProbabilities.fromJson(profile([1, 0, 0, 0, 0, 0, 0]));
    final b = EventProbabilities.fromJson(profile([0, 1, 0, 0, 0, 0, 0]));
    final mixed = EventProbabilities.matchup(a, b);
    equal(mixed.values, [0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0]);
    equal(mixed.sample(0).key, 'strikeout');
    equal(mixed.sample(0.499999).key, 'strikeout');
    equal(mixed.sample(0.5).key, 'walk');
    equal(mixed.sample(0.999999999).key, 'walk');
    for (final draw in [-0.1, 1.0, double.nan, double.infinity]) {
      throws(() => mixed.sample(draw));
    }
  });
  test('each of seven outcomes is selectable, including zero-weight edges', () {
    for (final event in PlateOutcome.values) {
      final weights = List<double>.filled(7, 0)..[event.index] = 1;
      final p = EventProbabilities.fromJson(profile(weights));
      equal(p.sample(0).key, event.key);
      equal(p.sample(0.999999999999).key, event.key);
    }
  });
  test('PRNG known vectors, seed validation and deterministic sequence', () {
    final random = SeededRandom(0);
    final states = <int>[];
    for (var i = 0; i < 3; i++) {
      random.nextDouble();
      states.add(random.state);
    }
    equal(states, [16807, 282475249, 1622650073]);
    throws(() => SeededRandom(-1));
    throws(() => SeededRandom(2147483646));
    final a = SeededRandom(42), b = SeededRandom(42);
    for (var i = 0; i < 100; i++) {
      equal(a.nextDouble(), b.nextDouble());
    }
  });
  test('walk force advances for all eight base configurations', () {
    final expectedBases = [
      ['B', null, null],
      ['B', '1', null],
      ['B', '2', null],
      ['B', '1', '2'],
      ['B', null, '3'],
      ['B', '1', '3'],
      ['B', '2', '3'],
      ['B', '1', '2'],
    ];
    for (var mask = 0; mask < 8; mask++) {
      final bases = List<String?>.generate(
        3,
        (i) => mask & (1 << i) == 0 ? null : '${i + 1}',
      );
      final result = advanceBases(bases, 'B', PlateOutcome.walk);
      equal(result.bases, expectedBases[mask]);
      equal(result.scored, mask == 7 ? ['3'] : []);
      equal(result.outsAdded, 0);
    }
  });
  test('all hit distances with loaded bases and scoring order', () {
    final outcomes = [
      PlateOutcome.single,
      PlateOutcome.doubleHit,
      PlateOutcome.triple,
      PlateOutcome.homeRun,
    ];
    final expectedBases = [
      ['B', '1', '2'],
      [null, 'B', '1'],
      [null, null, 'B'],
      [null, null, null],
    ];
    final expectedScored = [
      ['3'],
      ['3', '2'],
      ['3', '2', '1'],
      ['3', '2', '1', 'B'],
    ];
    for (var i = 0; i < 4; i++) {
      final result = advanceBases(['1', '2', '3'], 'B', outcomes[i]);
      equal(result.bases, expectedBases[i]);
      equal(result.scored, expectedScored[i]);
    }
  });
  test(
    'runner conservation and no mutation across all 56 base/outcome cases',
    () {
      for (var mask = 0; mask < 8; mask++) {
        for (final outcome in PlateOutcome.values) {
          final bases = List<String?>.generate(
            3,
            (i) => mask & (1 << i) == 0 ? null : '${i + 1}',
          );
          final before = List<String?>.of(bases);
          final result = advanceBases(bases, 'B', outcome);
          final remaining = result.bases.whereType<String>().toList();
          final all = [...remaining, ...result.scored];
          equal(
            all.length,
            bases.whereType<String>().length + (result.outsAdded == 0 ? 1 : 0),
          );
          equal(all.toSet().length, all.length);
          equal(bases, before);
        }
      }
    },
  );
  test('strikeout and other out preserve runners and add one out', () {
    for (final outcome in [PlateOutcome.strikeout, PlateOutcome.otherOut]) {
      final result = advanceBases(['1', null, '3'], 'B', outcome);
      equal(result.bases, ['1', null, '3']);
      equal(result.scored, []);
      equal(result.outsAdded, 1);
    }
  });
  test(
      'third out clears bases, switches sides and records third out in log detail',
      () {
    final before = GameState(
      outs: 2,
      bases: ['1', null, '3'],
      awayBattingIndex: 8,
    );
    final play = applyPlateAppearance(before, 'B', PlateOutcome.strikeout);
    equal(play.outsAfterPlay, 3);
    equal(play.basesAfterPlay, ['1', null, '3']);
    equal(play.state.bases, [null, null, null]);
    equal(play.state.outs, 0);
    check(!play.state.isTop, 'Expected bottom half');
    equal(play.state.awayBattingIndex, 0);
    equal(before.outs, 2);
  });
  test('team batting orders continue across innings independently', () {
    var state = GameState();
    for (var i = 0; i < 6; i++) {
      state = applyPlateAppearance(state, 'B', PlateOutcome.otherOut).state;
    }
    equal(
      [
        state.inning,
        state.isTop,
        state.awayBattingIndex,
        state.homeBattingIndex,
      ],
      [2, true, 3, 3],
    );
    equal(state.awayInnings, [0, 0]);
    equal(state.homeInnings, [0, null]);
  });
  test('skip bottom ninth when home is ahead', () {
    final state = applyPlateAppearance(
      late(top: true, outs: 2, away: 1, home: 2),
      'B',
      PlateOutcome.strikeout,
    ).state;
    equal(state.end?.name, 'homeAheadAfterTop');
    equal(state.homeInnings.last, null);
  });
  test('play bottom ninth when tied or away is ahead', () {
    for (final away in [0, 1]) {
      final state = applyPlateAppearance(
        late(top: true, outs: 2, away: away),
        'B',
        PlateOutcome.otherOut,
      ).state;
      check(!state.isFinished && !state.isTop, 'Expected bottom ninth');
      equal(state.homeInnings.last, 0);
    }
  });
  test('non-HR walk-off only credits winning run; HR credits all runners', () {
    for (final event in [
      PlateOutcome.doubleHit,
      PlateOutcome.triple,
      PlateOutcome.homeRun,
    ]) {
      final play = applyPlateAppearance(
        late(bases: ['1', '2', '3']),
        'B',
        event,
      );
      equal(play.state.end?.name, 'walkOff');
      equal(play.state.homeScore, event == PlateOutcome.homeRun ? 4 : 1);
    }
    final walk = applyPlateAppearance(
      late(outs: 2, bases: ['1', '2', '3']),
      'B',
      PlateOutcome.walk,
    );
    equal(walk.state.homeScore, 1);
    equal(walk.state.end?.name, 'walkOff');
  });
  test('ninth inning away win and extra-inning away win', () {
    for (final inning in [9, 10, 12]) {
      final state = applyPlateAppearance(
        late(inning: inning, away: 1, outs: 2),
        'B',
        PlateOutcome.strikeout,
      ).state;
      equal(state.end?.name, inning == 9 ? 'regulation' : 'extraInnings');
    }
  });
  test('tie after ninth starts tenth; tie after twelfth ends game', () {
    final extra = applyPlateAppearance(
      late(outs: 2),
      'B',
      PlateOutcome.otherOut,
    ).state;
    equal([extra.inning, extra.isTop, extra.isFinished], [10, true, false]);
    final end = applyPlateAppearance(
      late(inning: 12, outs: 2),
      'B',
      PlateOutcome.otherOut,
    ).state;
    equal(end.end?.name, 'tie');
    throws(() => applyPlateAppearance(end, 'B', PlateOutcome.homeRun));
  });
  test('walk-off allowed in extras and tying run does not finish game', () {
    final walkoff = applyPlateAppearance(
      late(inning: 12, bases: [null, null, '3']),
      'B',
      PlateOutcome.single,
    ).state;
    equal(walkoff.end?.name, 'walkOff');
    final tying = applyPlateAppearance(
      late(inning: 9, away: 1, bases: [null, null, '3']),
      'B',
      PlateOutcome.single,
    ).state;
    check(!tying.isFinished, 'Tying run must not end game');
    equal(tying.homeScore, 1);
  });
  test('all-out full game ends at exactly 72 PAs, 12 innings', () {
    var state = GameState();
    while (!state.isFinished) {
      state = applyPlateAppearance(state, 'B', PlateOutcome.strikeout).state;
    }
    equal(
      [state.plateAppearances, state.inning, state.awayScore, state.homeScore],
      [72, 12, 0, 0],
    );
    equal(state.end?.name, 'tie');
  });
  final ids = dataset.teams.keys.toList();
  GameEngine engine(int seed, {String? id}) => GameEngine(
        dataset: dataset,
        awayTeamId: ids[0],
        homeTeamId: ids[1],
        seed: seed,
        gameId: id ?? 'test-$seed',
      );
  test(
    'same seed and inputs reproduce full JSON; step and playToEnd agree',
    () {
      final a = engine(42), b = engine(42);
      a.playToEnd();
      while (!b.state.isFinished) {
        b.step();
      }
      equal(a.toJson(), b.toJson());
      throws(() => a.step());
      final count = a.logs.length;
      a.playToEnd();
      equal(a.logs.length, count);
    },
  );
  test('different seeds change play sequence; generated match IDs differ', () {
    final a = engine(42), b = engine(43);
    a.playToEnd();
    b.playToEnd();
    check(
      jsonEncode(a.logs.map((l) => l.draw).toList()) !=
          jsonEncode(b.logs.map((l) => l.draw).toList()),
      'Different seeds must vary',
    );
    final c = GameEngine(
      dataset: dataset,
      awayTeamId: ids[0],
      homeTeamId: ids[1],
      seed: 42,
    );
    final d = GameEngine(
      dataset: dataset,
      awayTeamId: ids[0],
      homeTeamId: ids[1],
      seed: 42,
    );
    check(c.gameId != d.gameId, 'Generated IDs must differ');
  });
  test('reject identical and unknown teams', () {
    throws(
      () => GameEngine(
        dataset: dataset,
        awayTeamId: ids[0],
        homeTeamId: ids[0],
        seed: 1,
      ),
    );
    throws(
      () => GameEngine(
        dataset: dataset,
        awayTeamId: 'unknown',
        homeTeamId: ids[1],
        seed: 1,
      ),
    );
  });
  test(
      'real-data games: totals, starter use, logs, score continuity, immutable snapshots',
      () {
    for (var i = 0; i < 10; i++) {
      final game = GameEngine(
        dataset: dataset,
        awayTeamId: ids[i],
        homeTeamId: ids[(i + 1) % 10],
        seed: 100 + i,
        gameId: 'pair-$i',
      );
      game.playToEnd();
      final state = game.state;
      equal(
        state.awayInnings.whereType<int>().fold<int>(0, (a, b) => a + b),
        state.awayScore,
      );
      equal(
        state.homeInnings.whereType<int>().fold<int>(0, (a, b) => a + b),
        state.homeScore,
      );
      equal(state.plateAppearances, game.logs.length);
      check(state.inning >= 9 && state.inning <= 12, 'Invalid final inning');
      var awayPAs = 0, homePAs = 0;
      for (final log in game.logs) {
        final battingTeam = log.isTop ? game.awayTeamId : game.homeTeamId;
        final defendingTeam = log.isTop ? game.homeTeamId : game.awayTeamId;
        equal(log.pitcherId, dataset.lineups[defendingTeam]!.pitcherId);
        final battingIndex = (log.isTop ? awayPAs++ : homePAs++) % 9;
        equal(
          log.batterId,
          dataset.lineups[battingTeam]!.battingOrder[battingIndex].playerId,
        );
        equal(
          log.after.awayScore +
              log.after.homeScore -
              log.before.awayScore -
              log.before.homeScore,
          log.transition.scored.length,
        );
        check(
          (log.probabilities.values.fold(0.0, (a, b) => a + b) - 1).abs() <
              1e-12,
          'Probability sum',
        );
        if (log.number > 1) {
          equal(game.logs[log.number - 2].after.toJson(), log.before.toJson());
        }
      }
      throws(() => state.bases[0] = 'mutation');
      throws(() => game.logs.clear());
      stdout.writeln(
        '  ${game.awayTeamId} ${state.awayScore}:${state.homeScore} ${game.homeTeamId} (${state.end!.name})',
      );
    }
  });
  test('1.1.0 without substitutions replays the week 2 example exactly', () {
    final file = File('../outputs/week2_example_game.json');
    check(file.existsSync(), 'Run from dart_engine/ so the example is found');
    final example = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final game = GameEngine(
      dataset: dataset,
      awayTeamId: example['away_team_id'] as String,
      homeTeamId: example['home_team_id'] as String,
      seed: example['seed'] as int,
      gameId: example['game_id'] as String,
    )..playToEnd();
    final now = game.toJson();
    for (final key in ['state', 'plate_appearances', 'random_state']) {
      equal(now[key], example[key]);
    }
    equal(now['substitutions'], []);
  });
  test('pitching change: new pitcher faces later batters, no re-entry', () {
    final game = engine(7);
    final home = ids[1];
    final starter = game.pitcherFor(home);
    final reliever = game.pitcherCandidates(home).first;
    check(!game.pitcherCandidates(home).contains(starter), 'Starter listed');
    for (var i = 0; i < 3; i++) {
      game.step();
    }
    final sub = game.substitutePitcher(home, reliever);
    equal(sub.outPlayerId, starter);
    equal(sub.beforePlateAppearance, game.state.plateAppearances + 1);
    game.playToEnd();
    for (final log in game.logs.where((l) => l.isTop)) {
      equal(log.pitcherId, log.number <= 3 ? starter : reliever);
    }
    throws(() => game.substitutePitcher(home, starter));
  });
  test('pinch hitter keeps the batting slot; replaced batter cannot return',
      () {
    final game = engine(8);
    final away = ids[0];
    final original = game.nextBatterFor(away);
    final pinch = game.pinchHitterCandidates(away).first;
    final sub = game.pinchHit(away, pinch);
    equal(sub.battingOrder, 1);
    equal(game.battingOrderFor(away).first, pinch);
    game.playToEnd();
    final awayLogs = game.logs.where((l) => l.isTop).toList();
    for (var i = 0; i < awayLogs.length; i += 9) {
      equal(awayLogs[i].batterId, pinch);
    }
    check(!awayLogs.any((l) => l.batterId == original), 'Original returned');
    throws(() => game.pinchHit(away, original));
  });
  test('reject ineligible substitutes and changes after the game', () {
    final game = engine(9);
    final away = ids[0], home = ids[1];
    throws(() => game.substitutePitcher(away, game.pitcherFor(home)));
    throws(() => game.pinchHit(away, game.battingOrderFor(away)[3]));
    throws(() => game.pinchHit(away, game.pinchHitterCandidates(home).first));
    throws(() => game.substitutePitcher('unknown', 'kbo:player:0'));
    game.playToEnd();
    throws(() => game.substitutePitcher(home, game.pitcherCandidates(home).first));
  });
  test('substitutions are logged and replay identically', () {
    GameEngine play() {
      final g = engine(10);
      for (var i = 0; i < 20; i++) {
        g.step();
      }
      g.substitutePitcher(ids[0], g.pitcherCandidates(ids[0]).first);
      g.pinchHit(ids[1], g.pinchHitterCandidates(ids[1]).last);
      return g..playToEnd();
    }

    final a = play(), b = play();
    equal(a.toJson(), b.toJson());
    equal((a.toJson()['substitutions'] as List).length, 2);
  });
  test('chosen starting pitchers pitch from the first plate appearance', () {
    final away = ids[0], home = ids[1];
    final auto = dataset.lineups[home]!.pitcherId;
    final candidates = GameEngine.starterCandidates(dataset, home);
    check(candidates.contains(auto), 'Automatic starter must be a candidate');
    final chosen = candidates.firstWhere((id) => id != auto);
    final game = GameEngine(
      dataset: dataset,
      awayTeamId: away,
      homeTeamId: home,
      seed: 11,
      gameId: 'starter-11',
      startingPitchers: {home: chosen},
    )..playToEnd();
    for (final log in game.logs.where((l) => l.isTop)) {
      equal(log.pitcherId, chosen);
    }
    equal(game.startingPitcherFor(home), chosen);
    equal(game.startingPitcherFor(away), dataset.lineups[away]!.pitcherId);
    equal((game.toJson()['starting_pitchers'] as Map)[home], chosen);
    check(game.substitutions.isEmpty, 'A chosen starter is not a substitution');
    // 바뀐 자동 선발은 교체 후보로 남는다 (경기에 나오지 않았으므로).
    final g2 = GameEngine(dataset: dataset, awayTeamId: away, homeTeamId: home, seed: 12, startingPitchers: {home: chosen});
    check(g2.pitcherCandidates(home).contains(auto), 'Unused starter should stay in the bullpen');
  });
  test('reject ineligible starting pitchers', () {
    final away = ids[0], home = ids[1];
    GameEngine make(Map<String, String> sp) =>
        GameEngine(dataset: dataset, awayTeamId: away, homeTeamId: home, seed: 1, startingPitchers: sp);
    throws(() => make({home: dataset.lineups[home]!.battingOrder.first.playerId}));
    throws(() => make({home: dataset.lineups[away]!.pitcherId}));
    throws(() => make({'unknown': dataset.lineups[home]!.pitcherId}));
  });
  stdout.writeln('\n$passed passed, ${failures.length} failed');
  // Optional positional arguments: dataset path, report output path.
  if (args.length > 1) {
    final report = File(args[1]);
    report.parent.createSync(recursive: true);
    report.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({
          'engine_version': GameEngine.version,
          'data_version': dataset.dataVersion,
          'dart_version': Platform.version,
          'dataset_path': datasetPath,
          'passed': passed,
          'failed': failures.length,
          'checks': checks,
          'scope':
              'Week 2 rules and real-data smoke tests; distribution calibration is week 5.',
        })}\n');
  }
  if (failures.isNotEmpty) exitCode = 1;
}
