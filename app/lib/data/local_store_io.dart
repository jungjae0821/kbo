import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_store.dart';

LocalStore createDeviceStore() => FileLocalStore(
      () async => Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}kbo_save'),
    );

/// 이름 하나가 파일 하나(`<이름>.json`)다. 임시 파일에 다 쓴 다음 원래 파일과 바꾼다.
class FileLocalStore implements LocalStore {
  FileLocalStore(this._directory);

  final Future<Directory> Function() _directory;
  Future<Directory>? _dir;

  // 같은 저장소의 읽기·쓰기는 차례대로 처리해 임시 파일이 서로 겹치지 않게 한다.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file(String name, [String suffix = '']) async {
    final dir = await (_dir ??= _directory().then((d) => d.create(recursive: true)));
    return File('${dir.path}${Platform.pathSeparator}$name.json$suffix');
  }

  @override
  Future<String?> read(String name) => _serial(() async {
        final file = await _file(name);
        if (!await file.exists()) return null;
        return file.readAsString();
      });

  @override
  Future<void> write(String name, String contents) => _serial(() async {
        final file = await _file(name);
        final temp = await _file(name, '.tmp');
        await temp.writeAsString(contents, flush: true);
        await temp.rename(file.path);
      });

  @override
  Future<void> delete(String name) => _serial(() async {
        final file = await _file(name);
        if (await file.exists()) await file.delete();
      });
}
