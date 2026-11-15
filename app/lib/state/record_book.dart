import 'package:flutter/foundation.dart';

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
  });

  final String gameId;
  final String awayTeamId;
  final String homeTeamId;
  final int awayScore;
  final int homeScore;
  final String predictedWinnerId;

  /// 무승부면 null.
  final String? winnerTeamId;
  final DateTime finishedAt;

  bool get isTie => winnerTeamId == null;
  bool get isHit => winnerTeamId == predictedWinnerId;
  int get points => isHit ? RecordBook.pointsPerHit : 0;
}

/// 개인 기록과 채점. 규칙은 README의 기획안을 따른다.
/// - 적중 +100점, 경기 ID당 한 번만 채점
/// - 무승부 0점, 적중률 분모에서 제외, 연속 적중 유지
///
/// 지금은 앱이 켜져 있는 동안만 보관한다. 기기 내 JSON 저장·복원은 4주 차.
class RecordBook extends ChangeNotifier {
  static const pointsPerHit = 100;

  final List<GameRecord> _games = [];
  int _currentStreak = 0;
  int _bestStreak = 0;

  List<GameRecord> get recent => List.unmodifiable(_games.reversed);
  int get predictionCount => _games.length;
  int get decidedCount => _games.where((g) => !g.isTie).length;
  int get hitCount => _games.where((g) => !g.isTie && g.isHit).length;
  int get totalPoints => _games.fold(0, (sum, g) => sum + g.points);
  int get currentStreak => _currentStreak;
  int get bestStreak => _bestStreak;

  /// 적중률. 승패가 갈린 경기가 없으면 null (화면에는 "—").
  double? get hitRate => decidedCount == 0 ? null : hitCount / decidedCount;

  bool isScored(String gameId) => _games.any((g) => g.gameId == gameId);

  /// 같은 경기 ID는 두 번 채점하지 않는다. 새로 채점했으면 true.
  bool score(GameRecord record) {
    if (isScored(record.gameId)) return false;
    _games.add(record);
    if (!record.isTie) {
      if (record.isHit) {
        _currentStreak++;
        if (_currentStreak > _bestStreak) _bestStreak = _currentStreak;
      } else {
        _currentStreak = 0;
      }
    }
    notifyListeners();
    return true;
  }
}
