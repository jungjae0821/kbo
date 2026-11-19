import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kbo_app/data/data_controller.dart';
import 'package:kbo_app/data/season_cache.dart';
import 'package:kbo_app/main.dart';
import 'package:kbo_app/state/record_book.dart';

class MemoryCache implements SeasonCache {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String source) async {
    if (fail) throw StateError('storage unavailable');
    values[key] = source;
  }
}

class SourceBundle extends CachingAssetBundle {
  SourceBundle(this.source);
  final String source;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode(source));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final raw = File('assets/data/season_dataset.json').readAsStringSync();
  const url = 'https://data.example.test/season.json';

  DataController controller(
    MemoryCache cache,
    Future<http.Response> Function(http.Request) send, {
    String? bundle,
    Duration timeout = const Duration(seconds: 10),
  }) => DataController(
    cache: cache,
    remoteUrl: url,
    bundle: SourceBundle(bundle ?? raw),
    clientFactory: () => MockClient(send),
    requestTimeout: timeout,
  );

  test('원격 JSON 검증 후 저장하고 새 컨트롤러가 오프라인에서 복원', () async {
    final cache = MemoryCache();
    final online = controller(cache, (r) async {
      expect(r.url.toString(), url);
      return http.Response.bytes(utf8.encode(raw), 200);
    });
    await online.load();
    expect(online.source, SeasonSource.network);
    expect(online.status, DataStatus.ready);
    expect(cache.values[online.cacheKey], raw);
    final offline = controller(
      cache,
      (_) async => throw http.ClientException('offline'),
      bundle: '{}',
    );
    await offline.load();
    expect(offline.source, SeasonSource.cache);
    expect(offline.data!.playerCount, 591);
    expect(offline.canRetry, isTrue);
  });

  for (final bad in [
    '{}',
    '<html>error</html>',
    jsonEncode(
      (jsonDecode(raw) as Map<String, dynamic>)..['season']['year'] = '2025',
    ),
    jsonEncode(
      (jsonDecode(raw) as Map<String, dynamic>)..['rules']['version'] = '1.0.0',
    ),
  ]) {
    test('잘못된 원격 입력이 정상 캐시를 덮어쓰지 않음 ${bad.length}', () async {
      final cache = MemoryCache();
      final data = controller(
        cache,
        (_) async => http.Response.bytes(utf8.encode(bad), 200),
      );
      cache.values[data.cacheKey] = raw;
      await data.load();
      expect(data.source, SeasonSource.cache);
      expect(cache.values[data.cacheKey], raw);
    });
  }

  test('HTTP 실패·손상 캐시는 번들로 대체하고 정상 캐시를 생성', () async {
    final cache = MemoryCache();
    final data = controller(
      cache,
      (_) async => http.Response('unavailable', 503),
    );
    cache.values[data.cacheKey] = '{}';
    await data.load();
    expect(data.source, SeasonSource.bundled);
    expect(data.status, DataStatus.ready);
    expect(data.notice, contains('앱에 포함된'));
    expect(cache.values[data.cacheKey], raw);
  });

  test('시간 초과 후 번들로 대체', () async {
    final data = controller(
      MemoryCache(),
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 5),
    );
    await data.load();
    expect(data.source, SeasonSource.bundled);
  });

  test('저장 장치 오류는 정상 원격 데이터 사용을 막지 않음', () async {
    final cache = MemoryCache()..fail = true;
    final data = controller(
      cache,
      (_) async => http.Response.bytes(utf8.encode(raw), 200),
    );
    await data.load();
    expect(data.status, DataStatus.ready);
    expect(data.source, SeasonSource.network);
    expect(data.notice, contains('보관하지 못했습니다'));
  });

  test('모든 입력 실패 후 재시도 성공·중복 요청 합치기', () async {
    var calls = 0;
    var recovered = false;
    final data = controller(MemoryCache(), (_) async {
      calls++;
      return http.Response.bytes(utf8.encode(recovered ? raw : '{}'), 200);
    }, bundle: '{}');
    final first = data.load();
    final second = data.load();
    expect(identical(first, second), isTrue);
    await first;
    expect(data.status, DataStatus.failed);
    expect(data.data, isNull);
    expect(data.error, isNotNull);
    recovered = true;
    await data.load();
    expect(data.status, DataStatus.ready);
    expect(data.error, isNull);
    expect(data.notice, isNull);
    expect(calls, 2);
  });

  test('원격 주소를 지정하지 않아도 번들·기기 캐시로 실행', () async {
    final cache = MemoryCache();
    final data = DataController(
      cache: cache,
      remoteUrl: '',
      bundle: SourceBundle(raw),
    );
    await data.load();
    expect(data.source, SeasonSource.bundled);
    expect(data.notice, isNull);
    final restored = DataController(
      cache: cache,
      remoteUrl: '',
      bundle: SourceBundle('{}'),
    );
    await restored.load();
    expect(restored.source, SeasonSource.cache);
  });

  testWidgets('캐시 대체 안내에서도 기존 시작 버튼과 재시도를 사용할 수 있음', (tester) async {
    final cache = MemoryCache();
    var recovered = false;
    final data = controller(
      cache,
      (_) async =>
          http.Response.bytes(utf8.encode(recovered ? raw : '{}'), 200),
    );
    cache.values[data.cacheKey] = raw;
    await tester.runAsync(data.load);
    expect(data.source, SeasonSource.cache);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.view.devicePixelRatio = 1;
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      for (final size in const [
        Size(360, 640),
        Size(768, 1024),
        Size(1280, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(KboApp(data: data, records: RecordBook()));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '경기 만들기'))
              .onPressed,
          isNotNull,
        );
        expect(find.text('다시 불러오기'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$brightness $size');
      }
    }
    recovered = true;
    await tester.runAsync(() async {
      await tester.tap(find.text('다시 불러오기'));
      await data.load();
    });
    await tester.pumpAndSettle();
    expect(data.source, SeasonSource.network);
    expect(find.text('다시 불러오기'), findsNothing);
  });

  testWidgets('오프라인 안내·기존 재시도 버튼·데이터 준비 전 시작 제한', (tester) async {
    var recovered = false;
    final data = controller(
      MemoryCache(),
      (_) async =>
          http.Response.bytes(utf8.encode(recovered ? raw : '{}'), 200),
      bundle: '{}',
    );
    await tester.runAsync(data.load);
    await tester.pumpWidget(KboApp(data: data, records: RecordBook()));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '경기 만들기'))
          .onPressed,
      isNull,
    );
    recovered = true;
    await tester.runAsync(() async {
      await tester.tap(find.text('다시 불러오기'));
      await data.load();
    });
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '경기 만들기'))
          .onPressed,
      isNotNull,
    );
    expect(find.text('다시 불러오기'), findsNothing);
  });
}
