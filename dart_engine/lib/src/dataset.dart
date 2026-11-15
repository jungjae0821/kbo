import 'probability.dart';

Map<String, dynamic> object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object');
  }
  return value;
}

String textField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected nonempty string: $key');
  }
  return value;
}

List<dynamic> arrayField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('Expected array: $key');
  return value;
}

class PlayerSeasonStats {
  PlayerSeasonStats.fromJson(Map<String, dynamic> json)
      : id = textField(json, 'player_id'),
        name = textField(json, 'player_name'),
        teamId = json['assigned_team_id'] as String?,
        batting = _profile(json, 'batting'),
        pitching = _profile(json, 'pitching'),
        validBatter = _eligible(json, 'batting'),
        validPitcher = _eligible(json, 'pitching');

  final String id;
  final String name;
  final String? teamId;
  final EventProbabilities? batting;
  final EventProbabilities? pitching;
  final bool validBatter;
  final bool validPitcher;

  static EventProbabilities? _profile(Map<String, dynamic> json, String role) {
    final profile = object(json['engine_profiles'])[role];
    return profile == null
        ? null
        : EventProbabilities.fromJson(object(object(profile)['probabilities']));
  }

  static bool _eligible(Map<String, dynamic> json, String role) {
    final value = object(json['engine_profiles'])[role];
    if (value == null) return false;
    final profile = object(value);
    return profile['sample_size'] is int &&
        (profile['sample_size'] as int) > 0 &&
        profile['fallback_reason'] == null &&
        arrayField(profile, 'missing_fields').isEmpty;
  }
}

class Team {
  Team.fromJson(Map<String, dynamic> json)
      : id = textField(json, 'team_id'),
        name = textField(json, 'team_name'),
        membershipNotice = textField(json, 'membership_notice'),
        rosterIds = Set.unmodifiable(
          arrayField(json, 'roster_player_ids').cast<String>(),
        );
  final String id;
  final String name;
  final String membershipNotice;
  final Set<String> rosterIds;
}

class LineupSlot {
  LineupSlot.fromJson(Map<String, dynamic> json)
      : order = json['order'] as int,
        playerId = textField(json, 'player_id'),
        position = textField(json, 'position_code');
  final int order;
  final String playerId;
  final String position;
}

class Lineup {
  Lineup.fromJson(Map<String, dynamic> json)
      : teamId = textField(json, 'team_id'),
        pitcherId = textField(json, 'starting_pitcher_id'),
        battingOrder = List.unmodifiable(
          arrayField(
            json,
            'batting_order',
          ).map((v) => LineupSlot.fromJson(object(v))).toList()
            ..sort((a, b) => a.order.compareTo(b.order)),
        );
  final String teamId;
  final String pitcherId;
  final List<LineupSlot> battingOrder;
}

class SeasonDataset {
  SeasonDataset._(this.dataVersion, this.teams, this.players, this.lineups);

  factory SeasonDataset.fromJson(Map<String, dynamic> json) {
    final rules = object(json['rules']);
    if (json['schema_version'] != '1.0.0' ||
        rules['version'] != '1.0.0' ||
        rules['matchup'] != 'arithmetic_mean_then_normalize' ||
        rules['max_innings'] != 12 ||
        rules['pitcher_usage'] != 'starter_for_entire_game' ||
        rules['prior_pa'] != 200 ||
        rules['prior_bf'] != 200 ||
        arrayField(rules, 'events').join(',') !=
            PlateOutcome.values.map((e) => e.key).join(',')) {
      throw const FormatException('Unsupported dataset schema or rules');
    }
    Map<String, T> index<T>(
      String key,
      T Function(Map<String, dynamic>) parse,
      String Function(T) id,
    ) {
      final result = <String, T>{};
      for (final value in arrayField(json, key)) {
        final model = parse(object(value));
        if (result.containsKey(id(model))) {
          throw FormatException('Duplicate $key ID: ${id(model)}');
        }
        result[id(model)] = model;
      }
      return Map.unmodifiable(result);
    }

    final teams = index('teams', Team.fromJson, (t) => t.id);
    final players = index('players', PlayerSeasonStats.fromJson, (p) => p.id);
    final lineups = index('lineups', Lineup.fromJson, (l) => l.teamId);
    if (teams.length < 2 || teams.length != lineups.length) {
      throw const FormatException('Each team requires exactly one lineup');
    }
    final selected = <String>{};
    for (final lineup in lineups.values) {
      final team = teams[lineup.teamId];
      if (team == null || lineup.battingOrder.length != 9) {
        throw const FormatException('Invalid lineup team or batter count');
      }
      final positions = <String>{};
      final ids = <String>[lineup.pitcherId];
      for (var i = 0; i < 9; i++) {
        final slot = lineup.battingOrder[i];
        if (slot.order != i + 1 ||
            !{
              'C',
              '1B',
              '2B',
              '3B',
              'SS',
              'LF',
              'CF',
              'RF',
              'DH',
            }.contains(slot.position) ||
            !positions.add(slot.position)) {
          throw const FormatException('Invalid batting order or position');
        }
        ids.add(slot.playerId);
      }
      for (var i = 0; i < ids.length; i++) {
        final player = players[ids[i]];
        if (player == null ||
            player.teamId != team.id ||
            !team.rosterIds.contains(ids[i]) ||
            !selected.add(ids[i]) ||
            !(i == 0 ? player.validPitcher : player.validBatter)) {
          throw FormatException('Invalid selected player: ${ids[i]}');
        }
      }
    }
    return SeasonDataset._(
      textField(json, 'data_version'),
      teams,
      players,
      lineups,
    );
  }

  final String dataVersion;
  final Map<String, Team> teams;
  final Map<String, PlayerSeasonStats> players;
  final Map<String, Lineup> lineups;
}
