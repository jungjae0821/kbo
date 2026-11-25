import 'dart:math' as math;

import 'dataset.dart';
import 'game.dart';
import 'probability.dart';

/// Totals for one side of many simulated games (a team, or the whole league).
class BattingTally {
  int games = 0;
  int plateAppearances = 0;
  int runs = 0;
  int runsAllowed = 0;
  int wins = 0;
  int losses = 0;
  int ties = 0;
  int doublePlays = 0;
  int runsScoredOnOuts = 0;
  final List<int> events = List.filled(PlateOutcome.values.length, 0);

  /// Sum of the matchup probabilities the engine sampled from, so sampled
  /// rates can be told apart from the inputs themselves.
  final List<double> expectedEvents =
      List.filled(PlateOutcome.values.length, 0);

  int count(PlateOutcome outcome) => events[outcome.index];
  double rate(PlateOutcome outcome) =>
      plateAppearances == 0 ? 0 : count(outcome) / plateAppearances;
  double get runsPerGame => games == 0 ? 0 : runs / games;

  /// Ties are left out of the denominator, as in the KBO standings.
  double? get winPercentage =>
      wins + losses == 0 ? null : wins / (wins + losses);

  int get hits =>
      count(PlateOutcome.single) +
      count(PlateOutcome.doubleHit) +
      count(PlateOutcome.triple) +
      count(PlateOutcome.homeRun);

  int get atBats =>
      plateAppearances -
      count(PlateOutcome.walk) -
      count(PlateOutcome.hitByPitch);

  double get battingAverage => atBats == 0 ? 0 : hits / atBats;
  double get onBasePercentage => plateAppearances == 0
      ? 0
      : (hits + count(PlateOutcome.walk) + count(PlateOutcome.hitByPitch)) /
          plateAppearances;

  Map<String, dynamic> toJson() => {
        'games': games,
        'plate_appearances': plateAppearances,
        'runs': runs,
        'runs_allowed': runsAllowed,
        'runs_per_game': runsPerGame,
        'wins': wins,
        'losses': losses,
        'ties': ties,
        'win_percentage': winPercentage,
        'event_rates': {
          for (final event in PlateOutcome.values) event.key: rate(event),
        },
        'expected_event_rates': {
          for (final event in PlateOutcome.values)
            event.key: plateAppearances == 0
                ? 0
                : expectedEvents[event.index] / plateAppearances,
        },
        'batting_average': battingAverage,
        'on_base_percentage': onBasePercentage,
        'double_plays_per_pa':
            plateAppearances == 0 ? 0 : doublePlays / plateAppearances,
        'runs_on_outs_per_pa':
            plateAppearances == 0 ? 0 : runsScoredOnOuts / plateAppearances,
      };
}

/// Running mean and variance (Welford) without keeping every value.
class RunningStats {
  int n = 0;
  double _mean = 0;
  double _m2 = 0;

  void add(num value) {
    n++;
    final delta = value - _mean;
    _mean += delta / n;
    _m2 += delta * (value - _mean);
  }

  double get mean => _mean;
  double get variance => n < 2 ? 0 : _m2 / (n - 1);
  double get standardDeviation => math.sqrt(variance);
}

/// Aggregates finished games. Only reads public engine state and logs, so the
/// engine itself is unchanged by batch runs.
class BatchSummary {
  BatchSummary(this.dataset);

  final SeasonDataset dataset;
  final BattingTally league = BattingTally();
  final Map<String, BattingTally> teams = {};
  int games = 0;
  int homeWins = 0;
  int awayWins = 0;
  int ties = 0;
  int extraInningGames = 0;
  int bottomNinthSkipped = 0;
  int walkOffs = 0;
  int maxPlateAppearances = 0;
  final RunningStats teamRuns = RunningStats();
  final RunningStats totalRuns = RunningStats();
  final RunningStats plateAppearances = RunningStats();

  /// Team runs in a game → number of team-games (0, 1, 2, ...).
  final Map<int, int> teamRunsHistogram = {};

  void add(GameEngine engine) {
    final state = engine.state;
    if (!state.isFinished) {
      throw StateError('Only finished games can be summarized');
    }
    games++;
    final away = teams.putIfAbsent(engine.awayTeamId, BattingTally.new);
    final home = teams.putIfAbsent(engine.homeTeamId, BattingTally.new);
    for (final (team, runs, allowed) in [
      (away, state.awayScore, state.homeScore),
      (home, state.homeScore, state.awayScore),
    ]) {
      team.games++;
      team.runs += runs;
      team.runsAllowed += allowed;
      league.games++;
      league.runs += runs;
      league.runsAllowed += allowed;
      teamRuns.add(runs);
      teamRunsHistogram[runs] = (teamRunsHistogram[runs] ?? 0) + 1;
      if (runs > allowed) {
        team.wins++;
        league.wins++;
      } else if (runs < allowed) {
        team.losses++;
        league.losses++;
      } else {
        team.ties++;
        league.ties++;
      }
    }
    totalRuns.add(state.awayScore + state.homeScore);
    plateAppearances.add(state.plateAppearances);
    maxPlateAppearances = math.max(maxPlateAppearances, state.plateAppearances);
    if (state.awayScore > state.homeScore) {
      awayWins++;
    } else if (state.homeScore > state.awayScore) {
      homeWins++;
    } else {
      ties++;
    }
    if (state.inning > 9) extraInningGames++;
    switch (state.end!) {
      case GameEnd.homeAheadAfterTop:
        if (state.inning == 9) bottomNinthSkipped++;
      case GameEnd.walkOff:
        walkOffs++;
      case GameEnd.regulation || GameEnd.extraInnings || GameEnd.tie:
        break;
    }
    for (final log in engine.logs) {
      final batting = log.isTop ? away : home;
      for (final tally in [batting, league]) {
        tally.plateAppearances++;
        tally.events[log.outcome.index]++;
        for (var i = 0; i < PlateOutcome.values.length; i++) {
          tally.expectedEvents[i] += log.probabilities.values[i];
        }
        if (log.transition.note == PlayNote.doublePlay) tally.doublePlays++;
        if (log.transition.note == PlayNote.runScoredOnOut) {
          tally.runsScoredOnOuts++;
        }
      }
    }
  }

  double get homeWinPercentage =>
      homeWins + awayWins == 0 ? 0 : homeWins / (homeWins + awayWins);
  double get tieRate => games == 0 ? 0 : ties / games;

  Map<String, dynamic> toJson() => {
        'games': games,
        'home_wins': homeWins,
        'away_wins': awayWins,
        'ties': ties,
        'tie_rate': tieRate,
        'home_win_percentage_excluding_ties': homeWinPercentage,
        'extra_inning_rate': games == 0 ? 0 : extraInningGames / games,
        'bottom_ninth_skipped_rate':
            games == 0 ? 0 : bottomNinthSkipped / games,
        'walk_off_rate': games == 0 ? 0 : walkOffs / games,
        'team_runs_per_game': {
          'mean': teamRuns.mean,
          'standard_deviation': teamRuns.standardDeviation,
        },
        'total_runs_per_game': {
          'mean': totalRuns.mean,
          'standard_deviation': totalRuns.standardDeviation,
        },
        'plate_appearances_per_game': {
          'mean': plateAppearances.mean,
          'standard_deviation': plateAppearances.standardDeviation,
          'max': maxPlateAppearances,
        },
        'team_runs_histogram': {
          for (final runs in (teamRunsHistogram.keys.toList()..sort()))
            '$runs': teamRunsHistogram[runs],
        },
        'league': league.toJson(),
      };
}

/// Plays [gamesPerMatchup] games for every (away, home) pair, without
/// substitutions, using each team's automatic lineup and starter. Every game
/// gets its own seed so matchups do not share random sequences.
BatchSummary simulateBatch(
  SeasonDataset dataset,
  List<(String, String)> matchups,
  int gamesPerMatchup, {
  int masterSeed = 20261125,
  BaserunningRates baserunning = GameEngine.defaultBaserunning,
  void Function(GameEngine engine)? onGame,
}) {
  final summary = BatchSummary(dataset);
  final seeds = spreadSeeds(
    matchups.length * gamesPerMatchup,
    masterSeed: masterSeed,
  );
  var next = 0;
  for (final (away, home) in matchups) {
    for (var i = 0; i < gamesPerMatchup; i++) {
      final seed = seeds[next++];
      final engine = GameEngine(
        dataset: dataset,
        awayTeamId: away,
        homeTeamId: home,
        seed: seed,
        gameId: 'batch-$away-$home-$seed',
        baserunning: baserunning,
      )..playToEnd();
      summary.add(engine);
      onGame?.call(engine);
    }
  }
  return summary;
}

/// Every ordered pair of different teams (each team hosts every other).
List<(String, String)> allMatchups(SeasonDataset dataset) => [
      for (final away in dataset.teams.keys)
        for (final home in dataset.teams.keys)
          if (away != home) (away, home),
    ];

/// Wilson score interval for a binomial proportion at about 95% confidence.
(double, double) wilsonInterval(int successes, int trials, {double z = 1.96}) {
  if (trials <= 0) throw ArgumentError.value(trials, 'trials');
  final p = successes / trials;
  final z2 = z * z;
  final denominator = 1 + z2 / trials;
  final center = (p + z2 / (2 * trials)) / denominator;
  final margin =
      z * math.sqrt(p * (1 - p) / trials + z2 / (4 * trials * trials)) /
          denominator;
  return (center - margin, center + margin);
}

/// Pearson correlation; null when either side has no variance.
double? pearson(List<double> xs, List<double> ys) {
  if (xs.length != ys.length || xs.length < 2) {
    throw ArgumentError('Need two equal-length lists of at least 2 values');
  }
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sxy += (xs[i] - mx) * (ys[i] - my);
    sxx += (xs[i] - mx) * (xs[i] - mx);
    syy += (ys[i] - my) * (ys[i] - my);
  }
  if (sxx == 0 || syy == 0) return null;
  return sxy / math.sqrt(sxx * syy);
}

/// Game seeds drawn uniformly over the whole range, as the app does with
/// `Random().nextInt(2147483645)`.
///
/// Neither consecutive seeds nor seeds taken from a Park–Miller stream are
/// valid samples: the first draw of seed s is `(s + 1) * 16807 / (2^31 - 1)`,
/// so small consecutive seeds all open with a strikeout, and a seed taken from
/// a Park–Miller stream *is* a state of that stream, so the games become
/// shifted copies of one sequence. `dart:math` Random is a different
/// generator, deterministic for a given seed on the Dart VM.
List<int> spreadSeeds(int count, {int masterSeed = 20261125}) {
  if (count < 0) throw ArgumentError.value(count, 'count');
  final master = math.Random(masterSeed);
  final seeds = <int>{};
  while (seeds.length < count) {
    seeds.add(master.nextInt(2147483646));
  }
  return seeds.toList();
}

/// Runs per nine innings when every plate appearance uses the dataset's
/// league baseline probabilities: what the engine's base-running structure
/// produces from an average lineup against an average pitcher.
double leagueAverageRunsPerNine(
  Map<String, dynamic> datasetJson,
  BaserunningRates rates, {
  int halfInnings = 100000,
  int seed = 7,
}) {
  final baselines = datasetJson['league_baselines'] as Map<String, dynamic>;
  final probabilities = EventProbabilities.fromJson(
    baselines['batting'] as Map<String, dynamic>,
  );
  final random = math.Random(seed);
  var runs = 0;
  for (var h = 0; h < halfInnings; h++) {
    var outs = 0;
    List<String?> bases = const [null, null, null];
    while (outs < 3) {
      final outcome = probabilities.sample(random.nextDouble());
      final advance = advanceBases(
        bases,
        'batter',
        outcome,
        outs: outs,
        draw: random.nextDouble,
        rates: rates,
      );
      outs += advance.outsAdded;
      // Runs never count on a play that makes the third out.
      if (outs < 3) runs += advance.scored.length;
      bases = advance.bases;
    }
  }
  return runs / halfInnings * 9;
}
