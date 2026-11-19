import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../data/local_store.dart';

/// 중단된 경기 한 건: 엔진 체크포인트와 내 예측.
class SavedGame {
  SavedGame({required this.checkpoint, required this.predictedWinnerId, required this.savedAt});

  factory SavedGame.decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } catch (_) {
      throw const FormatException('중단 경기 JSON이 아닙니다');
    }
    if (json is! Map || json['format'] != SavedGameStore.format) {
      throw const FormatException('중단 경기 형식이 아닙니다');
    }
    if (json['schema_version'] != SavedGameStore.schemaVersion) {
      throw FormatException('지원하지 않는 중단 경기 버전: ${json['schema_version']}');
    }
    final checkpoint = json['checkpoint'];
    final predicted = json['predicted_winner_id'];
    final rawSavedAt = json['saved_at'];
    final savedAt = rawSavedAt is String ? DateTime.tryParse(rawSavedAt) : null;
    if (checkpoint is! Map ||
        predicted is! String ||
        savedAt == null ||
        checkpoint['state'] is! Map ||
        (predicted != checkpoint['away_team_id'] && predicted != checkpoint['home_team_id'])) {
      throw const FormatException('중단 경기 내용이 올바르지 않습니다');
    }
    return SavedGame(
      checkpoint: checkpoint.cast<String, dynamic>(),
      predictedWinnerId: predicted,
      savedAt: savedAt,
    );
  }

  final Map<String, dynamic> checkpoint;
  final String predictedWinnerId;
  final DateTime savedAt;

  T _pick<T>(Map source, String key, T fallback) {
    final value = source[key];
    return value is T ? value : fallback;
  }

  Map get _state => checkpoint['state'] as Map;
  String get gameId => _pick(checkpoint, 'game_id', '');
  String get awayTeamId => _pick(checkpoint, 'away_team_id', '');
  String get homeTeamId => _pick(checkpoint, 'home_team_id', '');
  int get awayScore => _pick(_state, 'away_score', 0);
  int get homeScore => _pick(_state, 'home_score', 0);
  int get inning => _pick(_state, 'inning', 1);
  bool get isTop => _state['half'] != 'bottom';
  bool get isFinished => _state['finished'] == true;
  int get plateAppearances => _pick(checkpoint, 'plate_appearances', 0);
  String? get dataVersion => _pick<String?>(checkpoint, 'data_version', null);
  String? get engineVersion => _pick<String?>(checkpoint, 'engine_version', null);

  /// 지금 시즌 데이터·엔진으로 되살릴 수 있는가. 아니면 화면에서 이유를 알린다.
  bool compatibleWith(SeasonDataset dataset) =>
      dataVersion == dataset.dataVersion && engineVersion == GameEngine.version;

  /// 체크포인트를 다시 진행해 경기를 되살린다. 맞지 않으면 [FormatException].
  GameEngine restore(SeasonDataset dataset) => GameEngine.restore(dataset, checkpoint);

  String encode() => jsonEncode({
        'format': SavedGameStore.format,
        'schema_version': SavedGameStore.schemaVersion,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'predicted_winner_id': predictedWinnerId,
        'checkpoint': checkpoint,
      });
}

/// 진행 중인 경기를 타석·교체마다 기기에 저장하고, 앱을 다시 켜면 되살린다.
/// 경기가 끝나 채점하면 지운다. 한 번에 한 경기만 둔다.
class SavedGameStore extends ChangeNotifier {
  SavedGameStore({this.store});

  static const fileName = 'saved_game';
  static const format = 'kbo_saved_game';
  static const schemaVersion = 1;

  final LocalStore? store;

  SavedGame? _current;
  bool _loaded = false;
  bool _saveFailed = false;
  String? _notice;
  Future<void> _pending = Future.value();

  /// 이어서 할 수 있는 경기. 없으면 null.
  SavedGame? get current => _current;
  bool get isLoaded => _loaded || store == null;
  bool get saveFailed => _saveFailed;
  String? get notice => _notice;

  /// 진행 중인 저장이 모두 끝나면 완료된다.
  Future<void> get saved => _pending;

  Future<void> load() async {
    final store = this.store;
    if (store == null || _loaded) return;
    try {
      final source = await store.read(fileName);
      // 읽는 사이에 새 경기가 저장됐으면 그쪽이 최신이다.
      if (source != null && _current == null) _current = SavedGame.decode(source);
    } on FormatException {
      _notice = '중단된 경기 파일이 손상되어 이어할 수 없습니다.';
      _enqueue((s) => s.delete(fileName));
    } catch (_) {
      _notice = '기기에 저장된 중단 경기를 읽지 못했습니다.';
    }
    _loaded = true;
    notifyListeners();
  }

  /// 경기 상태를 저장한다. 화면은 기다리지 않아도 된다 (저장은 차례대로 처리).
  void save(GameEngine engine, String predictedWinnerId) {
    final game = SavedGame(
      checkpoint: engine.toCheckpoint(),
      predictedWinnerId: predictedWinnerId,
      savedAt: DateTime.now(),
    );
    final isNew = _current?.gameId != game.gameId;
    _current = game;
    _notice = null;
    final text = game.encode();
    _enqueue((s) => s.write(fileName, text));
    if (isNew) notifyListeners();
  }

  /// 채점을 마쳤거나 사용자가 버린 경기를 지운다. [gameId]가 주어지면 그 경기일 때만 지운다.
  void clear({String? gameId}) {
    if (gameId != null && _current != null && _current!.gameId != gameId) return;
    _current = null;
    _notice = null;
    _enqueue((s) => s.delete(fileName));
    notifyListeners();
  }

  void _enqueue(Future<void> Function(LocalStore store) action) {
    final store = this.store;
    if (store == null) return;
    _pending = _pending.then((_) async {
      try {
        await action(store);
        if (_saveFailed) {
          _saveFailed = false;
          notifyListeners();
        }
      } catch (_) {
        if (!_saveFailed) {
          _saveFailed = true;
          notifyListeners();
        }
      }
    });
  }
}
