import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';

LocalStore createDeviceStore() => PreferencesLocalStore();

/// 웹에는 파일이 없으므로 브라우저 저장소에 값 하나로 둔다. 값 하나를 바꾸는 것은 한 번에 일어난다.
class PreferencesLocalStore implements LocalStore {
  static const _prefix = 'kbo_store.';
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();

  @override
  Future<String?> read(String name) => _preferences.getString('$_prefix$name');

  @override
  Future<void> write(String name, String contents) => _preferences.setString('$_prefix$name', contents);

  @override
  Future<void> delete(String name) => _preferences.remove('$_prefix$name');
}
