import 'dart:convert';
import 'dart:io';

import '../lib/kbo_engine.dart';

const defaultDataset = '../kbo_data/kbo_2026_138278/app/season_dataset.json';

void main(List<String> args) {
  try {
    run(args);
  } catch (error) {
    stderr.writeln('Batch simulation failed: $error');
    exitCode = 1;
  }
}

void run(List<String> args) {
  const help = '''Usage (from dart_engine/):
  dart run bin/batch_simulate.dart [options]
  --dataset PATH      Season JSON (default: $defaultDataset)
  --seeds N           Seeds per ordered matchup, all 90 pairs (default: 100)
  --fixed-seeds N     Seeds for the single fixed matchup (default: 2000)
  --away ID           Fixed matchup away team (default: first team)
  --home ID           Fixed matchup home team (default: second team)
  --master-seed N     Master seed that draws the game seeds (default: 20261125)
  --output PATH       Save the JSON report
  --help              Show usage''';
  final options = <String, String>{};
  const valued = {
    '--dataset',
    '--seeds',
    '--fixed-seeds',
    '--away',
    '--home',
    '--master-seed',
    '--output',
  };
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help') {
      stdout.writeln(help);
      return;
    } else if (valued.contains(arg) &&
        i + 1 < args.length &&
        !args[i + 1].startsWith('--')) {
      options[arg] = args[++i];
    } else {
      throw ArgumentError('Unknown option or missing value: $arg\n$help');
    }
  }
  final path = options['--dataset'] ?? defaultDataset;
  final raw = jsonDecode(File(path).readAsStringSync(encoding: utf8))
      as Map<String, dynamic>;
  final dataset = SeasonDataset.fromJson(raw);
  final seedsPerMatchup = int.parse(options['--seeds'] ?? '100');
  final fixedSeeds = int.parse(options['--fixed-seeds'] ?? '2000');
  final masterSeed = int.parse(options['--master-seed'] ?? '20261125');
  if (seedsPerMatchup < 1 || fixedSeeds < 1) {
    throw ArgumentError('Seed counts must be positive');
  }
  final ids = dataset.teams.keys.toList();
  final fixedAway = options['--away'] ?? ids[0];
  final fixedHome = options['--home'] ?? ids[1];
  final watch = Stopwatch()..start();

  final fixed = simulateBatch(
    dataset,
    [(fixedAway, fixedHome)],
    fixedSeeds,
    masterSeed: masterSeed,
  );
  final league = simulateBatch(
    dataset,
    allMatchups(dataset),
    seedsPerMatchup,
    masterSeed: masterSeed + 1,
  );
  watch.stop();

  final real = realSeason(raw);
  final name = (String id) => dataset.teams[id]!.name;
  final awayFixed = fixed.teams[fixedAway]!;
  final (awayLow, awayHigh) =
      wilsonInterval(awayFixed.wins, awayFixed.wins + awayFixed.losses);

  final teamRows = <Map<String, dynamic>>[];
  final simWin = <double>[], realWin = <double>[];
  final simRuns = <double>[], realRuns = <double>[];
  for (final id in ids) {
    final sim = league.teams[id]!;
    final actual = (real['teams'] as Map<String, dynamic>)[id]
        as Map<String, dynamic>;
    simWin.add(sim.winPercentage!);
    realWin.add(actual['win_percentage'] as double);
    simRuns.add(sim.runsPerGame);
    realRuns.add(actual['runs_per_game'] as double);
    teamRows.add({
      'team_id': id,
      'team_name': name(id),
      'simulated': sim.toJson(),
      'real': actual,
    });
  }

  final simLeague = league.league;
  final realLeague = real['league'] as Map<String, dynamic>;
  final comparison = <String, dynamic>{
    'runs_per_team_game': _pair(
      simLeague.runsPerGame,
      realLeague['runs_per_team_game'],
    ),
    'tie_rate': _pair(league.tieRate, realLeague['tie_rate']),
    'batting_average': _pair(
      simLeague.battingAverage,
      realLeague['batting_average'],
    ),
    'double_plays_per_pa': _pair(
      simLeague.doublePlays / simLeague.plateAppearances,
      realLeague['gidp_per_pa'],
    ),
    'runs_on_outs_per_pa': _pair(
      simLeague.runsScoredOnOuts / simLeague.plateAppearances,
      realLeague['sacrifice_flies_per_pa'],
      note: 'Engine counts every run scoring on an out; KBO counts only '
          'sacrifice flies, so the engine value is expected to be higher',
    ),
    'event_rates': {
      for (final event in PlateOutcome.values)
        event.key: {
          ..._pair(
            simLeague.rate(event),
            (realLeague['event_rates'] as Map<String, dynamic>)[event.key],
          ),
          'engine_input_expected':
              simLeague.expectedEvents[event.index] /
                  simLeague.plateAppearances,
        },
    },
  };

  final report = <String, dynamic>{
    'generated_on': DateTime.now().toIso8601String().substring(0, 10),
    'engine_version': GameEngine.version,
    'data_version': dataset.dataVersion,
    'dart_version': Platform.version,
    'dataset_path': path,
    'command': 'dart run bin/batch_simulate.dart ${args.join(' ')}'.trim(),
    'seconds': watch.elapsedMilliseconds / 1000,
    'setup': {
      'lineups': 'automatic lineup and starter of each team, no substitutions',
      'seeds': 'distinct seeds per game from spreadSeeds; master seed '
          '$masterSeed for the fixed matchup and ${masterSeed + 1} for the '
          'league run',
      'fixed_matchup_games': fixedSeeds,
      'league_matchups': allMatchups(dataset).length,
      'league_seeds_per_matchup': seedsPerMatchup,
      'league_games': league.games,
    },
    'fixed_matchup': {
      'away_team_id': fixedAway,
      'away_team_name': name(fixedAway),
      'home_team_id': fixedHome,
      'home_team_name': name(fixedHome),
      'away_win_percentage_excluding_ties': awayFixed.winPercentage,
      'away_win_percentage_95ci': [awayLow, awayHigh],
      'away': awayFixed.toJson(),
      'home': fixed.teams[fixedHome]!.toJson(),
      'summary': fixed.toJson(),
    },
    'league': league.toJson(),
    'comparison_with_real_2026': comparison,
    'team_strength': {
      'win_percentage_correlation': pearson(simWin, realWin),
      'runs_per_game_correlation': pearson(simRuns, realRuns),
      'note': 'Real records include relievers, bench players, park and '
          'schedule; agreement is a sanity check, not a target',
      'teams': teamRows,
    },
    'real_2026_reference': real['league'],
  };

  _print(report, fixed, league, name);
  final output = options['--output'];
  if (output != null) {
    final file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      encoding: utf8,
    );
    stdout.writeln('보고서: ${file.absolute.path}');
  }
}

Map<String, dynamic> _pair(double simulated, dynamic real, {String? note}) {
  final actual = (real as num).toDouble();
  return {
    'simulated': simulated,
    'real': actual,
    'difference': simulated - actual,
    'ratio': actual == 0 ? null : simulated / actual,
    if (note != null) 'note': note,
  };
}

/// League and team reference values computed from the dataset's own season
/// totals. League event rates are the dataset's league baselines.
Map<String, dynamic> realSeason(Map<String, dynamic> raw) {
  final teams = <String, dynamic>{};
  var games = 0, runs = 0, ties = 0, pa = 0, ab = 0, hits = 0, sf = 0;
  for (final value in raw['teams'] as List) {
    final team = value as Map<String, dynamic>;
    final batting = team['batting'] as Map<String, dynamic>;
    final wins = team['wins'] as int, losses = team['losses'] as int;
    games += team['games'] as int;
    runs += team['runs_scored'] as int;
    ties += team['ties'] as int;
    pa += batting['plate_appearances'] as int;
    ab += batting['at_bats'] as int;
    hits += batting['hits'] as int;
    sf += batting['sacrifice_flies'] as int;
    teams[team['team_id'] as String] = {
      'games': team['games'],
      'wins': wins,
      'losses': losses,
      'ties': team['ties'],
      'win_percentage': wins / (wins + losses),
      'runs_per_game': (team['runs_scored'] as int) / (team['games'] as int),
      'runs_allowed_per_game':
          (team['runs_allowed'] as int) / (team['games'] as int),
    };
  }
  var gidp = 0, playerPa = 0;
  for (final value in raw['players'] as List) {
    final batting = (value as Map<String, dynamic>)['batting'];
    if (batting is! Map<String, dynamic>) continue;
    playerPa += (batting['plate_appearances'] as int?) ?? 0;
    gidp += (batting['grounded_into_double_plays'] as int?) ?? 0;
  }
  final baselines = raw['league_baselines'] as Map<String, dynamic>;
  return {
    'teams': teams,
    'league': {
      'team_games': games,
      'runs_per_team_game': runs / games,
      'tie_rate': ties / games,
      'plate_appearances': pa,
      'plate_appearances_per_team_game': pa / games,
      'batting_average': hits / ab,
      'sacrifice_flies_per_pa': sf / pa,
      'gidp_per_pa': gidp / playerPa,
      'event_rates': baselines['batting'],
      'event_rates_sample_pa': baselines['batting_sample_pa'],
    },
  };
}

String _pct(num value, [int digits = 1]) =>
    '${(value * 100).toStringAsFixed(digits)}%';

void _print(
  Map<String, dynamic> report,
  BatchSummary fixed,
  BatchSummary league,
  String Function(String) name,
) {
  final f = report['fixed_matchup'] as Map<String, dynamic>;
  final ci = f['away_win_percentage_95ci'] as List;
  stdout.writeln('== 고정 대진 ${f['away_team_name']}(원정) vs '
      '${f['home_team_name']}(홈), ${fixed.games}경기 ==');
  stdout.writeln('원정 승률 ${_pct(f['away_win_percentage_excluding_ties'])} '
      '(95% 구간 ${_pct(ci[0])}~${_pct(ci[1])}), 무승부 ${_pct(fixed.tieRate)}');
  stdout.writeln('팀 득점 평균 ${fixed.teamRuns.mean.toStringAsFixed(2)} '
      '(표준편차 ${fixed.teamRuns.standardDeviation.toStringAsFixed(2)})');
  stdout.writeln('');
  stdout.writeln('== 전체 90개 대진, ${league.games}경기 ==');
  final c = report['comparison_with_real_2026'] as Map<String, dynamic>;
  for (final key in [
    'runs_per_team_game',
    'tie_rate',
    'batting_average',
    'double_plays_per_pa',
    'runs_on_outs_per_pa',
  ]) {
    final row = c[key] as Map<String, dynamic>;
    stdout.writeln('${key.padRight(22)} 시뮬 '
        '${(row['simulated'] as double).toStringAsFixed(4)}  실제 '
        '${(row['real'] as double).toStringAsFixed(4)}');
  }
  stdout.writeln('사건            시뮬     입력기대  실제');
  for (final entry in (c['event_rates'] as Map<String, dynamic>).entries) {
    final row = entry.value as Map<String, dynamic>;
    stdout.writeln('${entry.key.padRight(14)} ${_pct(row['simulated'], 2).padLeft(7)}  '
        '${_pct(row['engine_input_expected'], 2).padLeft(7)}  '
        '${_pct(row['real'], 2).padLeft(7)}');
  }
  stdout.writeln('홈 승률(무승부 제외) ${_pct(league.homeWinPercentage)}, '
      '연장 ${_pct(league.toJson()['extra_inning_rate'])}');
  final strength = report['team_strength'] as Map<String, dynamic>;
  stdout.writeln('팀 승률 상관(시뮬↔실제) '
      '${(strength['win_percentage_correlation'] as double?)?.toStringAsFixed(3)}, '
      '팀 득점 상관 '
      '${(strength['runs_per_game_correlation'] as double?)?.toStringAsFixed(3)}');
  for (final row in strength['teams'] as List) {
    final r = row as Map<String, dynamic>;
    final sim = r['simulated'] as Map<String, dynamic>;
    final real = r['real'] as Map<String, dynamic>;
    stdout.writeln('  ${(r['team_name'] as String).padRight(8)} 시뮬 승률 '
        '${_pct(sim['win_percentage'])} 득점 '
        '${(sim['runs_per_game'] as double).toStringAsFixed(2)} | 실제 승률 '
        '${_pct(real['win_percentage'])} 득점 '
        '${(real['runs_per_game'] as double).toStringAsFixed(2)}');
  }
  stdout.writeln('소요 ${report['seconds']}초');
}
