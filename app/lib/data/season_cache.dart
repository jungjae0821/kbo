import 'package:shared_preferences/shared_preferences.dart';

/// 다시 내려받을 수 있는 시즌 JSON만 보관한다. 개인 기록 저장과는 별개다.
abstract interface class SeasonCache {
  Future<String?> read(String key);
  Future<void> write(String key, String source);
}

class PreferencesSeasonCache implements SeasonCache {
  // 플러그인 초기화도 실패할 수 있으므로 실제 읽기·쓰기 시점에 만든다.
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String source) =>
      _preferences.setString(key, source);
}
