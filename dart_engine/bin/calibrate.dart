import 'dart:convert';
import 'dart:io';

import '../lib/kbo_engine.dart';

const defaultDataset = '../kbo_data/kbo_2026_138278/app/season_dataset.json';

/// Sensitivity of league run scoring to the out-advancement rates, plus a
/// league-average-input baseline that separates engine structure from the
/// lineup/starter inputs. Evidence for the 2.1.0 calibration.
void main(List<String> args) {
  final output = args.isNotEmpty ? args.first : null;
  final raw = jsonDecode(File(defaultDataset).readAsStringSync(encoding: utf8))
      as Map<String, dynamic>;
  final dataset = SeasonDataset.fromJson(raw);
  final matchups = allMatchups(dataset);
  const gamesPerMatchup = 100;
  final realRuns = _realRunsPerTeamGame(raw);
  final rows = <Map<String, dynamic>>[];
  const previous = BaserunningRates(
    runnerFromSecondToThirdOnOut: 0,
    runnerFromFirstToSecondOnOut: 0,
  );
  final grid = <(String, BaserunningRates)>[
    ('2.0.0 (no advancement on outs)', previous),
    for (final second in [0.25, 0.35, 0.45])
      for (final first in [0.10, 0.20, 0.30])
        (
          '2B->3B $second, 1B->2B $first',
          BaserunningRates(
            runnerFromSecondToThirdOnOut: second,
            runnerFromFirstToSecondOnOut: first,
          ),
        ),
  ];
  for (final (label, rates) in grid) {
    final batch = simulateBatch(
      dataset,
      matchups,
      gamesPerMatchup,
      baserunning: rates,
    );
    final league = batch.league;
    rows.add({
      'label': label,
      'rates': rates.toJson(),
      'games': batch.games,
      'runs_per_team_game': league.runsPerGame,
      'tie_rate': batch.tieRate,
      'double_plays_per_pa': league.doublePlays / league.plateAppearances,
      'runs_on_outs_per_pa': league.runsScoredOnOuts / league.plateAppearances,
    });
    stdout.writeln('${label.padRight(32)} '
        '득점 ${league.runsPerGame.toStringAsFixed(3)} '
        '무승부 ${(batch.tieRate * 100).toStringAsFixed(1)}%');
  }
  final leagueInput = <Map<String, dynamic>>[
    for (final (label, rates) in [
      ('2.0.0', previous),
      ('2.1.0', GameEngine.defaultBaserunning),
    ])
      {
        'label': label,
        'runs_per_nine_innings':
            leagueAverageRunsPerNine(raw, rates, halfInnings: 400000),
      },
  ];
  for (final row in leagueInput) {
    stdout.writeln('리그 평균 입력 ${row['label']}: 9이닝 득점 '
        '${(row['runs_per_nine_innings'] as double).toStringAsFixed(3)}');
  }
  final report = {
    'generated_on': DateTime.now().toIso8601String().substring(0, 10),
    'engine_version': GameEngine.version,
    'data_version': dataset.dataVersion,
    'command': 'dart run bin/calibrate.dart ${args.join(' ')}'.trim(),
    'real_runs_per_team_game': realRuns,
    'games_per_setting': matchups.length * gamesPerMatchup,
    'seeds': 'spreadSeeds(masterSeed: 20261125), the same seeds for every '
        'setting so differences come from the rates',
    'out_advancement_sensitivity': rows,
    'league_average_input_baseline': {
      'description': 'Every plate appearance uses the league baseline '
          'probabilities; 400,000 half innings with dart:math Random(7)',
      'results': leagueInput,
    },
  };
  if (output != null) {
    File(output)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        encoding: utf8,
      );
    stdout.writeln('보고서: ${File(output).absolute.path}');
  }
}

double _realRunsPerTeamGame(Map<String, dynamic> raw) {
  var runs = 0, games = 0;
  for (final team in (raw['teams'] as List).cast<Map<String, dynamic>>()) {
    runs += team['runs_scored'] as int;
    games += team['games'] as int;
  }
  return runs / games;
}
