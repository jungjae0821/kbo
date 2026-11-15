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

class GameEngine {
  GameEngine({
    required this.dataset,
    required this.awayTeamId,
    required this.homeTeamId,
    required this.seed,
    String? gameId,
  })  : gameId = gameId ??
            'kbo-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
        _random = SeededRandom(seed) {
    if (awayTeamId == homeTeamId ||
        !dataset.teams.containsKey(awayTeamId) ||
        !dataset.teams.containsKey(homeTeamId)) {
      throw ArgumentError('Select two different teams from the dataset');
    }
    if (this.gameId.isEmpty) throw ArgumentError('gameId cannot be empty');
  }

  static const version = '1.0.0';
  static int _sequence = 0;
  final SeasonDataset dataset;
  final String awayTeamId;
  final String homeTeamId;
  final int seed;
  final String gameId;
  final SeededRandom _random;
  final List<PlateAppearanceLog> _logs = [];
  GameState _state = GameState();
  GameState get state => _state;
  List<PlateAppearanceLog> get logs => List.unmodifiable(_logs);

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
    final offense = dataset.lineups[state.isTop ? awayTeamId : homeTeamId]!;
    final defense = dataset.lineups[state.isTop ? homeTeamId : awayTeamId]!;
    final index = state.isTop ? state.awayBattingIndex : state.homeBattingIndex;
    final batter = dataset.players[offense.battingOrder[index].playerId]!;
    final pitcher = dataset.players[defense.pitcherId]!;
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
        'plate_appearances': _logs.map((log) => log.toJson()).toList(),
      };
}
