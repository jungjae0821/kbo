import 'local_store_web.dart' if (dart.library.io) 'local_store_io.dart' as platform;

/// 개인 기록·중단 경기처럼 다시 받을 수 없는 내 데이터를 기기에 둔다.
/// 시즌 JSON 캐시(`SeasonCache`)와는 별개다.
abstract interface class LocalStore {
  /// 없으면 null.
  Future<String?> read(String name);

  /// 쓰는 도중 앱이 꺼져도 이전 내용이나 새 내용 중 하나만 남는다.
  Future<void> write(String name, String contents);

  Future<void> delete(String name);
}

/// Android·데스크톱은 앱 전용 폴더의 파일, 웹은 브라우저 저장소.
LocalStore createDeviceStore() => platform.createDeviceStore();

/// 테스트와 저장소를 쓸 수 없는 환경용.
class MemoryLocalStore implements LocalStore {
  final Map<String, String> files = {};

  @override
  Future<String?> read(String name) async => files[name];

  @override
  Future<void> write(String name, String contents) async => files[name] = contents;

  @override
  Future<void> delete(String name) async => files.remove(name);
}
