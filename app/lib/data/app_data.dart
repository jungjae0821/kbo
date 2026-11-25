import 'dart:convert';

import 'package:kbo_engine/kbo_engine.dart';

/// 화면 표시용 팀 시즌 성적. 엔진 확률 계산에는 쓰지 않는다 (데이터 계약: 팀 지표는 비교 표시용).
class TeamSummary {
  TeamSummary({
    required this.id,
    required this.name,
    required this.games,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.runsScored,
    required this.runsAllowed,
    required this.battingAverage,
    required this.homeRuns,
    required this.era,
  });

  factory TeamSummary.fromJson(Map<String, dynamic> j) {
    final batting = (j['batting'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pitching = (j['pitching'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TeamSummary(
      id: j['team_id'] as String,
      name: j['team_name'] as String,
      games: j['games'] as int,
      wins: j['wins'] as int,
      losses: j['losses'] as int,
      ties: j['ties'] as int,
      runsScored: j['runs_scored'] as int,
      runsAllowed: j['runs_allowed'] as int,
      battingAverage: (batting['batting_average'] as num?)?.toDouble(),
      homeRuns: batting['home_runs'] as int?,
      era: (pitching['earned_run_average'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String name;
  final int games;
  final int wins;
  final int losses;
  final int ties;
  final int runsScored;
  final int runsAllowed;
  final double? battingAverage;
  final int? homeRuns;
  final double? era;

  /// "KT 위즈" → "KT", "삼성 라이온즈" → "삼성".
  String get shortName => name.split(' ').first;

  /// KBO 승률: 무승부를 제외한 승 / (승 + 패).
  double get winRate => wins + losses == 0 ? 0 : wins / (wins + losses);
}

/// 화면 표시용 선수 기록 (타격·투구 중 있는 것만).
class PlayerCard {
  PlayerCard({
    required this.id,
    required this.name,
    this.battingAverage,
    this.homeRuns,
    this.ops,
    this.era,
    this.wins,
    this.losses,
    this.inningsPitched,
    this.plateAppearances,
    this.outsPitched,
    this.saves,
    this.holds,
    this.pitcherStarts = 0,
  });

  factory PlayerCard.fromJson(Map<String, dynamic> j) {
    final b = (j['batting'] as Map?)?.cast<String, dynamic>();
    final p = (j['pitching'] as Map?)?.cast<String, dynamic>();
    // 시즌 수비 기록에서 투수로 선발 출장한 경기 수 (선발 등판 수로 쓴다).
    var starts = 0;
    for (final f in (j['fielding_by_position'] as List?) ?? const []) {
      if (f is Map && f['position'] == '투수' && f['starts'] is int) starts = f['starts'] as int;
    }
    return PlayerCard(
      id: j['player_id'] as String,
      name: j['player_name'] as String,
      battingAverage: (b?['batting_average'] as num?)?.toDouble(),
      homeRuns: b?['home_runs'] as int?,
      ops: (b?['ops'] as num?)?.toDouble(),
      era: (p?['earned_run_average'] as num?)?.toDouble(),
      wins: p?['wins'] as int?,
      losses: p?['losses'] as int?,
      inningsPitched: p?['innings_pitched'] as String?,
      plateAppearances: b?['plate_appearances'] as int?,
      outsPitched: p?['outs_pitched'] as int?,
      saves: p?['saves'] as int?,
      holds: p?['holds'] as int?,
      pitcherStarts: starts,
    );
  }

  final String id;
  final String name;
  final double? battingAverage;
  final int? homeRuns;
  final double? ops;
  final double? era;
  final int? wins;
  final int? losses;
  final String? inningsPitched;
  final int? plateAppearances;
  final int? outsPitched;
  final int? saves;
  final int? holds;

  /// 시즌에 선발투수로 나온 경기 수. 0이면 경기 전 선발 후보에서 뺀다.
  final int pitcherStarts;
}

/// 앱이 쓰는 시즌 데이터 한 벌. 엔진 입력은 [season]이 계약 검사를 통과한 것만 담는다.
class AppData {
  AppData._({
    required this.season,
    required this.year,
    required this.teams,
    required this.players,
  });

  /// JSON 문자열을 읽어 계약 검사까지 마친다. 잘못된 입력이면 [FormatException].
  factory AppData.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('시즌 데이터의 최상위가 객체가 아닙니다');
    }
    final season = SeasonDataset.fromJson(decoded);
    final teams = [
      for (final t in decoded['teams'] as List)
        TeamSummary.fromJson((t as Map).cast<String, dynamic>()),
    ];
    final players = {
      for (final p in decoded['players'] as List)
        (p as Map)['player_id'] as String: PlayerCard.fromJson(p.cast<String, dynamic>()),
    };
    final seasonInfo = (decoded['season'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AppData._(
      season: season,
      year: seasonInfo['year'] as String? ?? '',
      teams: List.unmodifiable(teams),
      players: Map.unmodifiable(players),
    );
  }

  final SeasonDataset season;
  final String year;
  final List<TeamSummary> teams;
  final Map<String, PlayerCard> players;

  TeamSummary team(String id) => teams.firstWhere((t) => t.id == id);
  PlayerCard player(String id) => players[id]!;
  int get playerCount => players.length;
}
