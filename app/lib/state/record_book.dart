import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local_store.dart';

/// 끝난 경기 한 건의 예측 결과.
class GameRecord {
  GameRecord({
    required this.gameId,
    required this.awayTeamId,
    required this.homeTeamId,
    required this.awayScore,
    required this.homeScore,
    required this.predictedWinnerId,
    required this.winnerTeamId,
    required this.finishedAt,
    this.engineVersion,
    this.dataVersion,
  });

  factory GameRecord.fromJson(Map<String, dynamic> j) {
    final rawFinishedAt = j['finished_at'];
    final finishedAt = rawFinishedAt is String ? DateTime.tryParse(rawFinishedAt) : null;
    final winner = j['winner_team_id'];
    if (j['game_id'] is! String ||
        (j['game_id'] as String).isEmpty ||
        j['away_team_id'] is! String ||
        j['home_team_id'] is! String ||
        j['away_score'] is! int ||
        j['home_score'] is! int ||
        j['predicted_winner_id'] is! String ||
        (winner != null && winner is! String) ||
        finishedAt == null) {
      throw const FormatException('경기 기록 항목이 올바르지 않습니다');
    }
    return GameRecord(
      gameId: j['game_id'] as String,
      awayTeamId: j['away_team_id'] as String,
      homeTeamId: j['home_team_id'] as String,
      awayScore: j['away_score'] as int,
      homeScore: j['home_score'] as int,
      predictedWinnerId: j['predicted_winner_id'] as String,
      winnerTeamId: winner as String?,
      finishedAt: finishedAt,
      engineVersion: j['engine_version'] is String ? j['engine_version'] as String : null,
      dataVersion: j['data_version'] is String ? j['data_version'] as String : null,
    );
  }

  final String gameId;
  final String awayTeamId;
  final String homeTeamId;
  final int awayScore;
  final int homeScore;
  final String predictedWinnerId;

  /// 무승부면 null.
  final String? winnerTeamId;
  final DateTime finishedAt;

  /// 이 경기를 치른 엔진·시즌 데이터 버전. 3주 차 이전 기록에는 없다.
  final String? engineVersion;
  final String? dataVersion;

  bool get isTie => winnerTeamId == null;
  bool get isHit => winnerTeamId == predictedWinnerId;
  int get points => isHit ? RecordBook.pointsPerHit : 0;

  Map<String, dynamic> toJson() => {
        'game_id': gameId,
        'away_team_id': awayTeamId,
        'home_team_id': homeTeamId,
        'away_score': awayScore,
        'home_score': homeScore,
        'predicted_winner_id': predictedWinnerId,
        'winner_team_id': winnerTeamId,
        'finished_at': finishedAt.toUtc().toIso8601String(),
        'engine_version': engineVersion,
        'data_version': dataVersion,
      };
}

/// 개인 기록과 채점. 규칙은 README의 기획안을 따른다.
/// - 적중 +100점, 경기 ID당 한 번만 채점 (앱을 다시 켜도 유지)
/// - 무승부 0점, 적중률 분모에서 제외, 연속 적중 유지
///
/// [store]가 있으면 채점할 때마다 기기에 JSON으로 저장하고 [load]로 되살린다.
class RecordBook extends ChangeNotifier {
  RecordBook({this.store});

  static const pointsPerHit = 100;
  static const fileName = 'records';
  static const corruptFileName = 'records.corrupt';
  static const format = 'kbo_records';
  static const schemaVersion = 1;

  final LocalStore? store;

  final List<GameRecord> _games = [];
  int _currentStreak = 0;
  int _bestStreak = 0;
  bool _loaded = false;
  String? _notice;
  bool _saveFailed = false;
  Future<void> _pending = Future.value();

  List<GameRecord> get recent => List.unmodifiable(_games.reversed);
  int get predictionCount => _games.length;
  int get decidedCount => _games.where((g) => !g.isTie).length;
  int get hitCount => _games.where((g) => !g.isTie && g.isHit).length;
  int get totalPoints => _games.fold(0, (sum, g) => sum + g.points);
  int get currentStreak => _currentStreak;
  int get bestStreak => _bestStreak;

  /// 저장된 기록을 다 읽었는가. 저장소가 없으면 처음부터 true.
  bool get isLoaded => _loaded || store == null;

  /// 읽기·저장에 문제가 있을 때 화면에 보여 줄 안내.
  String? get notice => _saveFailed ? '기록을 기기에 저장하지 못했습니다. 앱을 닫으면 이번 기록이 사라질 수 있습니다.' : _notice;

  /// 진행 중인 저장이 모두 끝나면 완료된다.
  Future<void> get saved => _pending;

  /// 적중률. 승패가 갈린 경기가 없으면 null (화면에는 "—").
  double? get hitRate => decidedCount == 0 ? null : hitCount / decidedCount;

  bool isScored(String gameId) => _games.any((g) => g.gameId == gameId);

  /// 같은 경기 ID는 두 번 채점하지 않는다. 새로 채점했으면 true.
  bool score(GameRecord record) {
    if (isScored(record.gameId)) return false;
    _games.add(record);
    _apply(record);
    notifyListeners();
    _save();
    return true;
  }

  void _apply(GameRecord record) {
    if (record.isTie) return;
    if (record.isHit) {
      _currentStreak++;
      if (_currentStreak > _bestStreak) _bestStreak = _currentStreak;
    } else {
      _currentStreak = 0;
    }
  }

  /// 저장된 기록을 읽는다. 파일이 손상됐으면 따로 보관하고 빈 기록으로 시작한다.
  Future<void> load() async {
    final store = this.store;
    if (store == null || _loaded) return;
    List<GameRecord> stored = const [];
    try {
      final source = await store.read(fileName);
      if (source != null) {
        try {
          stored = decode(source);
        } on FormatException {
          await store.write(corruptFileName, source);
          _notice = '저장된 개인 기록이 손상되어 읽지 못했습니다. 새 기록으로 시작합니다.';
        }
      }
    } catch (_) {
      _notice = '기기에 저장된 개인 기록을 읽지 못했습니다.';
    }
    // 읽는 사이에 끝난 경기가 있으면 뒤에 붙인다.
    final added = List.of(_games);
    _games
      ..clear()
      ..addAll(stored);
    for (final g in added) {
      if (!isScored(g.gameId)) _games.add(g);
    }
    _currentStreak = 0;
    _bestStreak = 0;
    _games.forEach(_apply);
    _loaded = true;
    notifyListeners();
    if (added.isNotEmpty) _save();
  }

  /// 저장 형식을 해석한다. 같은 경기 ID가 두 번 있으면 처음 것만 남긴다.
  static List<GameRecord> decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } catch (_) {
      throw const FormatException('개인 기록 JSON이 아닙니다');
    }
    if (json is! Map || json['format'] != format) {
      throw const FormatException('개인 기록 형식이 아닙니다');
    }
    if (json['schema_version'] != schemaVersion) {
      throw FormatException('지원하지 않는 기록 버전: ${json['schema_version']}');
    }
    final games = json['games'];
    if (games is! List) throw const FormatException('경기 목록이 없습니다');
    final seen = <String>{};
    return [
      for (final g in games)
        if (g is Map) GameRecord.fromJson(g.cast<String, dynamic>()) else throw const FormatException('경기 기록 항목이 올바르지 않습니다'),
    ].where((g) => seen.add(g.gameId)).toList();
  }

  String encode() => const JsonEncoder.withIndent(' ').convert({
        'format': format,
        'schema_version': schemaVersion,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'total_points': totalPoints,
        'prediction_count': predictionCount,
        'decided_count': decidedCount,
        'hit_count': hitCount,
        'current_streak': currentStreak,
        'best_streak': bestStreak,
        'games': _games.map((g) => g.toJson()).toList(),
      });

  void _save() {
    final store = this.store;
    // 읽기 전에 저장하면 기존 파일을 덮어쓰므로, 끝난 경기는 load()가 합쳐서 저장한다.
    if (store == null || !_loaded) return;
    _pending = _pending.then((_) async {
      try {
        await store.write(fileName, encode());
        if (_saveFailed) {
          _saveFailed = false;
          notifyListeners();
        }
      } catch (_) {
        _saveFailed = true;
        notifyListeners();
      }
    });
  }
}
