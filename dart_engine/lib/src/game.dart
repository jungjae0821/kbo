import 'dataset.dart';
import 'probability.dart';

enum GameEnd { homeAheadAfterTop, walkOff, regulation, extraInnings, tie }

class BaseAdvance {
  BaseAdvance(List<String?> bases, List<String> scored, this.outsAdded)
      : bases = List.unmodifiable(bases),
        scored = List.unmodifiable(scored);
  final List<String?> bases;
  final List<String> scored;
  final int outsAdded;
}

/// Bases are [first, second, third]. Scoring order starts at third base.
BaseAdvance advanceBases(
  List<String?> bases,
  String batterId,
  PlateOutcome outcome,
) {
  if (bases.length != 3) throw ArgumentError('Exactly three bases required');
  final next = List<String?>.of(bases);
  final scored = <String>[];
  if (outcome == PlateOutcome.strikeout || outcome == PlateOutcome.otherOut) {
    return BaseAdvance(next, scored, 1);
  }
  if (outcome == PlateOutcome.walk) {
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
  final distance = switch (outcome) {
    PlateOutcome.single => 1,
    PlateOutcome.doubleHit => 2,
    PlateOutcome.triple => 3,
    PlateOutcome.homeRun => 4,
    _ => throw StateError('Unsupported outcome'),
  };
  next.fillRange(0, 3, null);
  for (var base = 2; base >= 0; base--) {
    if (bases[base] == null) continue;
    if (base + distance >= 3) {
      scored.add(bases[base]!);
    } else {
      next[base + distance] = bases[base];
    }
  }
  if (distance == 4) {
    scored.add(batterId);
  } else {
    next[distance - 1] = batterId;
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
    this.scored,
  );
  final GameState state;
  final List<String?> basesAfterPlay;
  final int outsAfterPlay;
  final List<String> scored;
}

/// Pure rules, separate from probability sampling and the Flutter UI.
PlayTransition applyPlateAppearance(
  GameState before,
  String batterId,
  PlateOutcome outcome,
) {
  if (before.isFinished) throw StateError('Game is already finished');
  if (before.inning < 1 ||
      before.inning > 12 ||
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
  final advance = advanceBases(before.bases, batterId, outcome);
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
  } else if (outs == 3) {
    if (isTop) {
      if (inning >= 9 && homeScore > awayScore) {
        end = GameEnd.homeAheadAfterTop;
      } else {
        isTop = false;
        homeInnings[inning - 1] = 0;
      }
    } else if (inning >= 9 && awayScore != homeScore) {
      end = inning == 9 ? GameEnd.regulation : GameEnd.extraInnings;
    } else if (inning == 12) {
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

  /// 1.1.0: pitching changes and pinch hitters. Without substitutions a game
  /// replays exactly as in 1.0.0 for the same inputs and seed.
  static const version = '1.1.0';
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

  /// Replaces [teamId]'s pitcher from the next plate appearance on.
  Substitution substitutePitcher(String teamId, String playerId) {
    _checkSubstitution(teamId, playerId, pitcherCandidates(teamId));
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
    final transition = applyPlateAppearance(state, batter.id, outcome);
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

  Map<String, dynamic> toJson() => {
        'game_id': gameId,
        'engine_version': version,
        'data_version': dataset.dataVersion,
        'seed': seed,
        'random_algorithm': SeededRandom.algorithm,
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
