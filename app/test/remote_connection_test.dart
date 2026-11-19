import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kbo_app/data/data_controller.dart';
import 'package:kbo_app/data/remote_config.dart';
import 'package:kbo_app/data/season_cache.dart';
import 'package:kbo_engine/kbo_engine.dart';

class _Cache implements SeasonCache {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String source) async => values[key] = source;
}

class _NoBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw StateError('Bundle disabled for live verification');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('VERIFY_OCI_REMOTE');

  test(
    '실제 OCI HTTPS → 계약 검사 → 경기 종료 → 오프라인 캐시 복원',
    () async {
      // Flutter 테스트의 의도적인 HTTP 400 모의 처리를 이 명시적 실통신 검사에서만 해제한다.
      // 실제 HttpClient의 인증서 검증과 HTTPS는 그대로 사용한다.
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previous);
      final cache = _Cache();
      final controller = DataController(cache: cache, bundle: _NoBundle());
      addTearDown(controller.dispose);
      expect(controller.remoteUrl, defaultSeasonDataUrl);
      await controller.load();
      expect(controller.error, isNull);
      expect(controller.status, DataStatus.ready);
      expect(controller.source, SeasonSource.network);
      expect(controller.notice, isNull);
      expect(controller.data!.playerCount, 591);

      final downloaded = cache.values[controller.cacheKey]!;
      final bundled = File('assets/data/season_dataset.json')
          .readAsStringSync();
      expect(
        jsonEncode(jsonDecode(downloaded)),
        jsonEncode(jsonDecode(bundled)),
      );
      final season = controller.data!.season;
      final ids = season.teams.keys.toList();
      final game = GameEngine(
        dataset: season,
        awayTeamId: ids[0],
        homeTeamId: ids[1],
        seed: 42,
      );
      game.playToEnd();
      expect(game.state.isFinished, isTrue);

      final offline = DataController(
        cache: cache,
        bundle: _NoBundle(),
        clientFactory: () => _OfflineClient(),
      );
      addTearDown(offline.dispose);
      await offline.load();
      expect(offline.status, DataStatus.ready);
      expect(offline.source, SeasonSource.cache);
      expect(offline.data!.season.dataVersion, season.dataVersion);
    },
    skip: !enabled ? '실서버 검증은 --dart-define=VERIFY_OCI_REMOTE=true로 실행' : false,
  );
}

class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw http.ClientException(
        'Intentional offline verification',
        request.url,
      );
}
