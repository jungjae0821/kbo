import 'dart:convert';

import 'dataset.dart';
import 'probability.dart';

enum GameEnd { homeAheadAfterTop, walkOff, regulation, extraInnings, tie }

/// KBO regular season: extra innings end after the 11th (since 2025).
const maxInnings = 11;

/// Situational base-running odds applied on top of the plate outcome.
///
/// Hit advancement rates are long-run professional averages. The double play
/// and run-scoring-out rates were calibrated so simulated 2026 games match
/// the league's GIDP and sacrifice fly totals per plate appearance (see
/// dart_engine/README.md).
class BaserunningRates {
  const BaserunningRates({
    this.singleRunnerFromSecondScores = 0.60,
    this.singleRunnerFromFirstToThird = 0.28,
    this.doubleRunnerFromFirstScores = 0.42,
    this.doublePlay = 0.18,
    this.runnerFromThirdScoresOnOut = 0.52,
  });

  /// Single: runner on second scores instead of stopping at third.
  final double singleRunnerFromSecondScores;

  /// Single: runner on first takes third when it is open.
  final double singleRunnerFromFirstToThird;

  /// Double: runner on first scores instead of stopping at third.
  final double doubleRunnerFromFirstScores;

  /// Other out with a runner on first and fewer than two outs.
  final double doublePlay;

  /// Other out (not a double play) with a runner on third and fewer than two
  /// outs: sacrifice fly or run-scoring groundout.
  final double runnerFromThirdScoresOnOut;

  Map<String, double> toJson() => {
        'single_runner_from_second_scores': singleRunnerFromSecondScores,
        'single_runner_from_first_to_third': singleRunnerFromFirstToThird,
        'double_runner_from_first_scores': doubleRunnerFromFirstScores,
        'double_play': doublePlay,
        'runner_from_third_scores_on_out': runnerFromThirdScoresOnOut,
      };
}

/// What happened beyond the plate outcome itself, for logs and the UI.
enum PlayNote {
  doublePlay('double_play'),
  runScoredOnOut('run_scored_on_out');

  const PlayNote(this.key);
  final String key;
}

class BaseAdvance {
  BaseAdvance(
    List<String?> bases,
    List<String> scored,
    this.outsAdded, {
    this.note,
    List<double> draws = const [],
  })  : bases = List.unmodifiable(bases),
        scored = List.unmodifiable(scored),
        draws = List.unmodifiable(draws);
  final List<String?> bases;
  final List<String> scored;
  final int outsAdded;
  final PlayNote? note;

  /// Random draws consumed for situational base running, in order.
  final List<double> draws;
}

/// Bases are [first, second, third]. Scoring order starts at third base.
///
/// [outs] is the number of outs before the play. [draw] supplies uniform
/// values in [0, 1) for situational base running; without it, every
/// situational event (extra base, double play, run on an out) is skipped.
BaseAdvance advanceBases(
  List<String?> bases,
  String batterId,
  PlateOutcome outcome, {
  int outs = 0,
  double Function()? draw,
  BaserunningRates rates = const BaserunningRates(),
}) {
  if (bases.length != 3) throw ArgumentError('Exactly three bases required');
  final draws = <double>[];
  bool chance(double probability) {
    if (draw == null) return false;
    final value = draw();
    draws.add(value);
    return value < probability;
  }

  final next = List<String?>.of(bases);
  final scored = <String>[];
  if (outcome == PlateOutcome.strikeout) {
    return BaseAdvance(next, scored, 1);
  }
  if (outcome == PlateOutcome.otherOut) {
    if (outs < 2 && next[0] != null && chance(rates.doublePlay)) {
      // Batter and the runner from first are out; others move up one base,
      // but no run counts when the double play ends the inning.
      final inningOver = outs + 2 >= 3;
      final third = next[2], second = next[1];
      next.fillRange(0, 3, null);
      if (!inningOver) {
        if (third != null) scored.add(third);
        next[2] = second;
      } else {
        next[1] = second;
        next[2] = third;
      }
      return BaseAdvance(next, scored, 2,
          note: PlayNote.doublePlay, draws: draws);
    }
    if (outs < 2 &&
        next[2] != null &&
        chance(rates.runnerFromThirdScoresOnOut)) {
      scored.add(next[2]!);
      next[2] = null;
      return BaseAdvance(next, scored, 1,
          note: PlayNote.runScoredOnOut, draws: draws);
    }
    return BaseAdvance(next, scored, 1, draws: draws);
  }
  if (outcome == PlateOutcome.single) {
    if (next[2] != null) scored.add(next[2]!);
    next[2] = null;
    if (next[1] != null) {
      if (chance(rates.singleRunnerFromSecondScores)) {
        scored.add(next[1]!);
      } else {
        next[2] = next[1];
      }
      next[1] = null;
    }
    if (next[0] != null) {
      if (next[2] == null && chance(rates.singleRunnerFromFirstToThird)) {
        next[2] = next[0];
      } else {
        next[1] = next[0];
      }
    }
    next[0] = batterId;
    return BaseAdvance(next, scored, 0, draws: draws);
  }
  if (outcome == PlateOutcome.doubleHit) {
    for (final base in [2, 1]) {
      if (next[base] != null) scored.add(next[base]!);
    }
    final first = next[0];
    next.fillRange(0, 3, null);
    if (first != null) {
      if (chance(rates.doubleRunnerFromFirstScores)) {
        scored.add(first);
      } else {
        next[2] = first;
      }
    }
    next[1] = batterId;
    return BaseAdvance(next, scored, 0, draws: draws);
  }
  if (outcome == PlateOutcome.walk || outcome == PlateOutcome.hitByPitch) {
    if (next[0] != null) {
      if (next[1] != null) {
        if (next[2] != null) scored.add(next[2]!);
        next[2] = next[1];
      }
      next[1] = next[0];
    }
    next[0] = batterId;
    return BaseAdvance(next, scored, 0);
  }
  // Triple and home run: every runner scores.
  for (var base = 2; base >= 0; base--) {
    if (bases[base] != null) scored.add(bases[base]!);
  }
  next.fillRange(0, 3, null);
  if (outcome == PlateOutcome.homeRun) {
    scored.add(batterId);
  } else {
    next[2] = batterId;
  }
  return BaseAdvance(next, scored, 0);
}

/// Immutable snapshot. Inning scores use null for an unplayed half inning.
class GameState {
  GameState({
    this.inning = 1,
    this.isTop = true,
    this.outs = 0,
    List<String?> bases = const [null, null, null],
    this.awayScore = 0,
    this.homeScore = 0,
    this.awayBattingIndex = 0,
    this.homeBattingIndex = 0,
    List<int?> awayInnings = const [0],
    List<int?> homeInnings = const [null],
    this.plateAppearances = 0,
    this.end,
  })  : bases = List.unmodifiable(bases),
        awayInnings = List.unmodifiable(awayInnings),
        homeInnings = List.unmodifiable(homeInnings);

  final int inning;
  final bool isTop;
  final int outs;
  final List<String?> bases;
  final int awayScore;
  final int homeScore;
  final int awayBattingIndex;
  final int homeBattingIndex;
  final List<int?> awayInnings;
  final List<int?> homeInnings;
  final int plateAppearances;
  final GameEnd? end;
  bool get isFinished => end != null;

  Map<String, dynamic> toJson() => {
        'inning': inning,
        'half': isTop ? 'top' : 'bottom',
        'outs': outs,
        'bases': bases,
        'away_score': awayScore,
        'home_score': homeScore,
        'away_batting_index': awayBattingIndex,
        'home_batting_index': homeBattingIndex,
        'away_innings': awayInnings,
        'home_innings': homeInnings,
        'plate_appearances': plateAppearances,
        'finished': isFinished,
        'end_reason': end?.name,
      };
}

class PlayTransition {
  PlayTransition(
    this.state,
    this.basesAfterPlay,
    this.outsAfterPlay,
    this.scored, {
    this.note,
    this.draws = const [],
  });
  final GameState state;
  final List<String?> basesAfterPlay;
  final int outsAfterPlay;
  final List<String> scored;
  final PlayNote? note;

  /// Random draws consumed for situational base running.
  final List<double> draws;
}

/// Pure rules, separate from probability sampling and the Flutter UI.
PlayTransition applyPlateAppearance(
  GameState before,
  String batterId,
  PlateOutcome outcome, {
  double Function()? draw,
  BaserunningRates rates = const BaserunningRates(),
}) {
  if (before.isFinished) throw StateError('Game is already finished');
  if (before.inning < 1 ||
      before.inning > maxInnings ||
      before.outs < 0 ||
      before.outs > 2 ||
      before.bases.length != 3 ||
      before.awayInnings.length != before.inning ||
      before.homeInnings.length != before.inning ||
      before.awayBattingIndex < 0 ||
      before.awayBattingIndex > 8 ||
      before.homeBattingIndex < 0 ||
      before.homeBattingIndex > 8) {
    throw ArgumentError('Invalid game state');
  }
  final advance = advanceBases(
    before.bases,
    batterId,
    outcome,
    outs: before.outs,
    draw: draw,
    rates: rates,
  );
  var scored = advance.scored;
  // Non-HR walk-offs stop when the winning run crosses home.
  if (!before.isTop &&
      before.inning >= 9 &&
      outcome != PlateOutcome.homeRun &&
      before.homeScore + scored.length > before.awayScore) {
    final needed = before.awayScore - before.homeScore + 1;
    scored = List.unmodifiable(scored.take(needed));
  }
  final awayScore = before.awayScore + (before.isTop ? scored.length : 0);
  final homeScore = before.homeScore + (before.isTop ? 0 : scored.length);
  final awayInnings = List<int?>.of(before.awayInnings);
  final homeInnings = List<int?>.of(before.homeInnings);
  final battingInnings = before.isTop ? awayInnings : homeInnings;
  battingInnings[before.inning - 1] =
      (battingInnings[before.inning - 1] ?? 0) + scored.length;
  var inning = before.inning;
  var isTop = before.isTop;
  var outs = before.outs + advance.outsAdded;
  var bases = advance.bases;
  GameEnd? end;
  if (!isTop && inning >= 9 && homeScore > awayScore) {
    end = GameEnd.walkOff;
  } else if (outs >= 3) {
    if (isTop) {
      if (inning >= 9 && homeScore > awayScore) {
        end = GameEnd.homeAheadAfterTop;
      } else {
        isTop = false;
        homeInnings[inning - 1] = 0;
      }
    } else if (inning >= 9 && awayScore != homeScore) {
      end = inning == 9 ? GameEnd.regulation : GameEnd.extraInnings;
    } else if (inning == maxInnings) {
      end = GameEnd.tie;
    } else {
      inning++;
      isTop = true;
      awayInnings.add(0);
      homeInnings.add(null);
    }
    if (end == null) {
      outs = 0;
      bases = const [null, null, null];
    }
  }
  return PlayTransition(
    GameState(
      inning: inning,
      isTop: isTop,
      outs: outs,
      bases: bases,
      awayScore: awayScore,
      homeScore: homeScore,
      awayBattingIndex: before.isTop
          ? (before.awayBattingIndex + 1) % 9
          : before.awayBattingIndex,
      homeBattingIndex: before.isTop
          ? before.homeBattingIndex
          : (before.homeBattingIndex + 1) % 9,
      awayInnings: awayInnings,
      homeInnings: homeInnings,
      plateAppearances: before.plateAppearances + 1,
      end: end,
    ),
    advance.bases,
    before.outs + advance.outsAdded,
    scored,
    note: advance.note,
    draws: advance.draws,
  );
}

class PlateAppearanceLog {
  PlateAppearanceLog({
    required this.number,
    required this.inning,
    required this.isTop,
    required this.batterId,
    required this.pitcherId,
    required this.outcome,
    required this.probabilities,
    required this.draw,
    required this.randomState,
    required this.before,
    required this.transition,
  });
  final int number;
  final int inning;
  final bool isTop;
  final String batterId;
  final String pitcherId;
  final PlateOutcome outcome;
  final EventProbabilities probabilities;
  final double draw;
  final int randomState;
  final GameState before;
  final PlayTransition transition;
  GameState get after => transition.state;

  Map<String, dynamic> toJson() => {
        'number': number,
        'inning': inning,
        'half': isTop ? 'top' : 'bottom',
        'batter_id': batterId,
        'pitcher_id': pitcherId,
        'outcome': outcome.key,
        'probabilities': probabilities.toJson(),
        'draw': draw,
        'random_state_after': randomState,
        'runs': transition.scored.length,
        'scored_player_ids': transition.scored,
        'bases_after_play': transition.basesAfterPlay,
        'outs_after_play': transition.outsAfterPlay,
        'play_note': transition.note?.key,
        'baserunning_draws': transition.draws,
        'before': before.toJson(),
        'after': after.toJson(),
      };
}

enum SubstitutionKind {
  pitcher('pitcher'),
  pinchHitter('pinch_hitter');

  const SubstitutionKind(this.key);
  final String key;
}

/// A substitution applied between plate appearances. [beforePlateAppearance]
/// is the number of the first plate appearance that uses the new player.
class Substitution {
  Substitution({
    required this.kind,
    required this.teamId,
    required this.outPlayerId,
    required this.inPlayerId,
    required this.beforePlateAppearance,
    required this.inning,
    required this.isTop,
    this.battingOrder,
  });

  final SubstitutionKind kind;
  final String teamId;
  final String outPlayerId;
  final String inPlayerId;
  final int beforePlateAppearance;
  final int inning;
  final bool isTop;

  /// 1-9 for a pinch hitter; null for a pitching change.
  final int? battingOrder;

  Map<String, dynamic> toJson() => {
        'kind': kind.key,
        'team_id': teamId,
        'out_player_id': outPlayerId,
        'in_player_id': inPlayerId,
        'before_plate_appearance': beforePlateAppearance,
        'inning': inning,
        'half': isTop ? 'top' : 'bottom',
        'batting_order': battingOrder,
      };
}

class GameEngine {
  GameEngine({
    required this.dataset,
    required this.awayTeamId,
    required this.homeTeamId,
    required this.seed,
    String? gameId,
    Map<String, String> startingPitchers = const {},
  })  : gameId = gameId ??
            'kbo-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
        _random = SeededRandom(seed) {
    if (awayTeamId == homeTeamId ||
        !dataset.teams.containsKey(awayTeamId) ||
        !dataset.teams.containsKey(homeTeamId)) {
      throw ArgumentError('Select two different teams from the dataset');
    }
    if (this.gameId.isEmpty) throw ArgumentError('gameId cannot be empty');
    for (final teamId in startingPitchers.keys) {
      if (teamId != awayTeamId && teamId != homeTeamId) {
        throw ArgumentError.value(teamId, 'startingPitchers', 'Team is not in this game');
      }
    }
    for (final teamId in [awayTeamId, homeTeamId]) {
      final lineup = dataset.lineups[teamId]!;
      final starter = startingPitchers[teamId] ?? lineup.pitcherId;
      if (!starterCandidates(dataset, teamId).contains(starter)) {
        throw ArgumentError.value(
          starter,
          'startingPitchers',
          'Not an eligible starter: off the roster, no usable pitching record, '
              'or already in the batting order',
        );
      }
      _pitchers[teamId] = starter;
      _orders[teamId] = lineup.battingOrder.map((s) => s.playerId).toList();
      _appeared[teamId] = {starter, ..._orders[teamId]!};
    }
  }

  /// Pitchers who may start for [teamId]: on its roster, with a usable
  /// pitching profile, and not in its automatic batting order. Includes the
  /// automatic starter.
  static List<String> starterCandidates(SeasonDataset dataset, String teamId) {
    final team = dataset.teams[teamId];
    final lineup = dataset.lineups[teamId];
    if (team == null || lineup == null) {
      throw ArgumentError.value(teamId, 'teamId', 'Unknown team');
    }
    final batters = {for (final s in lineup.battingOrder) s.playerId};
    return [
      for (final id in team.rosterIds)
        if (!batters.contains(id) &&
            dataset.players[id]?.teamId == teamId &&
            dataset.players[id]!.validPitcher)
          id,
    ]..sort();
  }

  /// The pitcher who started for [teamId].
  String startingPitcherFor(String teamId) {
    _team(teamId);
    final first = _substitutions
        .where((s) => s.teamId == teamId && s.kind == SubstitutionKind.pitcher)
        .firstOrNull;
    return first?.outPlayerId ?? _pitchers[teamId]!;
  }

  /// 2.0.0: hit by pitch, situational base running (extra bases, double
  /// plays, runs on outs), 11-inning limit and the one-batter minimum for
  /// pitchers. Games from 1.x do not replay under 2.0.0.
  static const version = '2.0.0';
  static const baserunning = BaserunningRates();
  static int _sequence = 0;
  final SeasonDataset dataset;
  final String awayTeamId;
  final String homeTeamId;
  final int seed;
  final String gameId;
  final SeededRandom _random;
  final List<PlateAppearanceLog> _logs = [];
  final Map<String, String> _pitchers = {};
  final Map<String, List<String>> _orders = {};
  final Map<String, Set<String>> _appeared = {};
  final List<Substitution> _substitutions = [];
  GameState _state = GameState();
  GameState get state => _state;
  List<PlateAppearanceLog> get logs => List.unmodifiable(_logs);
  List<Substitution> get substitutions => List.unmodifiable(_substitutions);

  /// The pitcher currently assigned to [teamId].
  String pitcherFor(String teamId) => _pitchers[_team(teamId)]!;

  /// Player IDs in batting order 1-9 as currently assigned to [teamId].
  List<String> battingOrderFor(String teamId) =>
      List.unmodifiable(_orders[_team(teamId)]!);

  /// The batter who comes up next for [teamId].
  String nextBatterFor(String teamId) =>
      _orders[_team(teamId)]![_battingIndex(teamId)];

  /// Everyone who has played in this game for [teamId]; none may re-enter.
  Set<String> appearedFor(String teamId) =>
      Set.unmodifiable(_appeared[_team(teamId)]!);

  /// Roster pitchers with a usable pitching profile who have not played yet.
  List<String> pitcherCandidates(String teamId) =>
      _candidates(teamId, (p) => p.validPitcher);

  /// Roster batters with a usable batting profile who have not played yet.
  List<String> pinchHitterCandidates(String teamId) =>
      _candidates(teamId, (p) => p.validBatter);

  /// Batters the current pitcher of [teamId] has faced in this game.
  int battersFacedByCurrentPitcher(String teamId) {
    final pitcher = pitcherFor(teamId);
    return _logs.where((log) => log.pitcherId == pitcher).length;
  }

  /// A pitcher must face at least one batter before being replaced
  /// (Official Baseball Rules 5.10(f), (g)).
  bool canSubstitutePitcher(String teamId) =>
      !state.isFinished && battersFacedByCurrentPitcher(teamId) > 0;

  /// Replaces [teamId]'s pitcher from the next plate appearance on.
  Substitution substitutePitcher(String teamId, String playerId) {
    _checkSubstitution(teamId, playerId, pitcherCandidates(teamId));
    if (!canSubstitutePitcher(teamId)) {
      throw StateError(
        'The current pitcher must face at least one batter before a change',
      );
    }
    final sub = _record(Substitution(
      kind: SubstitutionKind.pitcher,
      teamId: teamId,
      outPlayerId: _pitchers[teamId]!,
      inPlayerId: playerId,
      beforePlateAppearance: state.plateAppearances + 1,
      inning: state.inning,
      isTop: state.isTop,
    ));
    _pitchers[teamId] = playerId;
    return sub;
  }

  /// Sends [playerId] up for [teamId]'s next batter. The pinch hitter keeps
  /// that batting slot for the rest of the game.
  Substitution pinchHit(String teamId, String playerId) {
    _checkSubstitution(teamId, playerId, pinchHitterCandidates(teamId));
    final index = _battingIndex(teamId);
    final sub = _record(Substitution(
      kind: SubstitutionKind.pinchHitter,
      teamId: teamId,
      outPlayerId: _orders[teamId]![index],
      inPlayerId: playerId,
      beforePlateAppearance: state.plateAppearances + 1,
      inning: state.inning,
      isTop: state.isTop,
      battingOrder: index + 1,
    ));
    _orders[teamId]![index] = playerId;
    return sub;
  }

  String _team(String teamId) {
    if (teamId != awayTeamId && teamId != homeTeamId) {
      throw ArgumentError.value(teamId, 'teamId', 'Team is not in this game');
    }
    return teamId;
  }

  int _battingIndex(String teamId) => _team(teamId) == awayTeamId
      ? state.awayBattingIndex
      : state.homeBattingIndex;

  List<String> _candidates(
    String teamId,
    bool Function(PlayerSeasonStats) usable,
  ) {
    final team = dataset.teams[_team(teamId)]!;
    final appeared = _appeared[teamId]!;
    return [
      for (final id in team.rosterIds)
        if (!appeared.contains(id) &&
            dataset.players[id]?.teamId == teamId &&
            usable(dataset.players[id]!))
          id,
    ]..sort();
  }

  void _checkSubstitution(
    String teamId,
    String playerId,
    List<String> candidates,
  ) {
    if (state.isFinished) throw StateError('Game is already finished');
    if (!candidates.contains(playerId)) {
      throw ArgumentError.value(
        playerId,
        'playerId',
        'Not an eligible substitute: off the roster, no usable record, '
            'or already played in this game',
      );
    }
  }

  Substitution _record(Substitution sub) {
    _substitutions.add(sub);
    _appeared[sub.teamId]!.add(sub.inPlayerId);
    return sub;
  }

  String? get winnerTeamId =>
      !state.isFinished || state.homeScore == state.awayScore
          ? null
          : state.homeScore > state.awayScore
              ? homeTeamId
              : awayTeamId;

  PlateAppearanceLog step() {
    if (state.isFinished) throw StateError('Game is already finished');
    // Guard pathological inputs without inventing a final score or result.
    if (state.plateAppearances >= 10000) {
      throw StateError(
        'Exceeded 10000 plate appearances; game remains unfinished',
      );
    }
    final offenseId = state.isTop ? awayTeamId : homeTeamId;
    final defenseId = state.isTop ? homeTeamId : awayTeamId;
    final batter = dataset.players[nextBatterFor(offenseId)]!;
    final pitcher = dataset.players[_pitchers[defenseId]]!;
    final probabilities = EventProbabilities.matchup(
      batter.batting!,
      pitcher.pitching!,
    );
    final draw = _random.nextDouble();
    final outcome = probabilities.sample(draw);
    final transition = applyPlateAppearance(
      state,
      batter.id,
      outcome,
      draw: _random.nextDouble,
      rates: baserunning,
    );
    final log = PlateAppearanceLog(
      number: state.plateAppearances + 1,
      inning: state.inning,
      isTop: state.isTop,
      batterId: batter.id,
      pitcherId: pitcher.id,
      outcome: outcome,
      probabilities: probabilities,
      draw: draw,
      randomState: _random.state,
      before: state,
      transition: transition,
    );
    _state = transition.state;
    _logs.add(log);
    return log;
  }

  GameState playToEnd() {
    while (!state.isFinished) {
      step();
    }
    return state;
  }

  static const checkpointFormat = 'kbo_game_checkpoint';
  static const checkpointVersion = 1;

  /// The smallest record that rebuilds this game exactly: the game is
  /// deterministic, so [restore] replays the plate appearances with the same
  /// seed and substitutions. Random state and the current state are kept to
  /// detect a checkpoint that no longer replays to the same point.
  Map<String, dynamic> toCheckpoint() => {
        'format': checkpointFormat,
        'checkpoint_version': checkpointVersion,
        'game_id': gameId,
        'engine_version': version,
        'data_version': dataset.dataVersion,
        'random_algorithm': SeededRandom.algorithm,
        'seed': seed,
        'away_team_id': awayTeamId,
        'home_team_id': homeTeamId,
        'starting_pitchers': {
          awayTeamId: startingPitcherFor(awayTeamId),
          homeTeamId: startingPitcherFor(homeTeamId),
        },
        'substitutions': _substitutions.map((s) => s.toJson()).toList(),
        'plate_appearances': state.plateAppearances,
        'random_state': _random.state,
        'state': state.toJson(),
      };

  /// Rebuilds a game from [toCheckpoint]. Throws [FormatException] when the
  /// checkpoint is malformed, was made by another engine or data version, or
  /// does not replay to the saved state.
  factory GameEngine.restore(
    SeasonDataset dataset,
    Map<String, dynamic> checkpoint,
  ) {
    T field<T>(String key) {
      final value = checkpoint[key];
      if (value is! T) throw FormatException('Checkpoint field "$key" is invalid');
      return value;
    }

    if (checkpoint['format'] != checkpointFormat ||
        checkpoint['checkpoint_version'] != checkpointVersion) {
      throw const FormatException('Not a supported game checkpoint');
    }
    if (field<String>('engine_version') != version) {
      throw FormatException(
          'Checkpoint engine ${checkpoint['engine_version']} != $version');
    }
    if (field<String>('data_version') != dataset.dataVersion) {
      throw FormatException(
          'Checkpoint data ${checkpoint['data_version']} != ${dataset.dataVersion}');
    }
    if (field<String>('random_algorithm') != SeededRandom.algorithm) {
      throw const FormatException('Checkpoint random algorithm differs');
    }
    final target = field<int>('plate_appearances');
    if (target < 0 || target > 10000) {
      throw const FormatException('Checkpoint plate appearance count is invalid');
    }
    final subs = field<List>('substitutions').map((raw) {
      if (raw is! Map) throw const FormatException('Checkpoint substitution is invalid');
      final kind = SubstitutionKind.values
          .where((k) => k.key == raw['kind'])
          .firstOrNull;
      final before = raw['before_plate_appearance'];
      if (kind == null ||
          raw['team_id'] is! String ||
          raw['in_player_id'] is! String ||
          raw['out_player_id'] is! String ||
          before is! int) {
        throw const FormatException('Checkpoint substitution is invalid');
      }
      return raw.cast<String, dynamic>();
    }).toList();

    final GameEngine engine;
    try {
      engine = GameEngine(
        dataset: dataset,
        awayTeamId: field<String>('away_team_id'),
        homeTeamId: field<String>('home_team_id'),
        seed: field<int>('seed'),
        gameId: field<String>('game_id'),
        startingPitchers: field<Map>('starting_pitchers').map(
          (k, v) => MapEntry(k as String, v as String),
        ),
      );
      var next = 0;
      void applyDue() {
        while (next < subs.length &&
            subs[next]['before_plate_appearance'] ==
                engine.state.plateAppearances + 1) {
          final s = subs[next++];
          final teamId = s['team_id'] as String;
          final expectedOut = s['kind'] == SubstitutionKind.pitcher.key
              ? engine.pitcherFor(teamId)
              : engine.nextBatterFor(teamId);
          if (expectedOut != s['out_player_id']) {
            throw const FormatException('Checkpoint substitution does not replay');
          }
          if (s['kind'] == SubstitutionKind.pitcher.key) {
            engine.substitutePitcher(teamId, s['in_player_id'] as String);
          } else {
            engine.pinchHit(teamId, s['in_player_id'] as String);
          }
        }
      }

      while (engine.state.plateAppearances < target) {
        applyDue();
        if (engine.state.isFinished) {
          throw const FormatException('Checkpoint replays past the end of the game');
        }
        engine.step();
      }
      applyDue();
      if (next != subs.length) {
        throw const FormatException('Checkpoint has substitutions that never replay');
      }
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Checkpoint does not replay: $error');
    }
    final saved = checkpoint['state'];
    if (checkpoint['random_state'] != engine._random.state ||
        (saved != null && jsonEncode(saved) != jsonEncode(engine.state.toJson()))) {
      throw const FormatException('Checkpoint does not replay to the saved state');
    }
    return engine;
  }

  Map<String, dynamic> toJson() => {
        'game_id': gameId,
        'engine_version': version,
        'data_version': dataset.dataVersion,
        'seed': seed,
        'random_algorithm': SeededRandom.algorithm,
        'max_innings': maxInnings,
        'baserunning_rates': baserunning.toJson(),
        'random_state': _random.state,
        'away_team_id': awayTeamId,
        'home_team_id': homeTeamId,
        'winner_team_id': winnerTeamId,
        'state': state.toJson(),
        'starting_pitchers': {
          awayTeamId: startingPitcherFor(awayTeamId),
          homeTeamId: startingPitcherFor(homeTeamId),
        },
        'substitutions': _substitutions.map((s) => s.toJson()).toList(),
        'plate_appearances': _logs.map((log) => log.toJson()).toList(),
      };
}
