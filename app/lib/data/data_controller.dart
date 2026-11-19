import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_data.dart';
import 'season_cache.dart';

enum DataStatus { loading, ready, failed }

enum SeasonSource { network, cache, bundled }

/// 원격 → 검증된 기기 캐시 → 번들 순서로 같은 시즌의 데이터를 준비한다.
class DataController extends ChangeNotifier {
  DataController({
    AssetBundle? bundle,
    SeasonCache? cache,
    http.Client Function()? clientFactory,
    this.remoteUrl = const String.fromEnvironment('KBO_DATA_URL'),
    this.requestTimeout = const Duration(seconds: 10),
  }) : _bundle = bundle ?? rootBundle,
       _cache = cache ?? PreferencesSeasonCache(),
       _clientFactory = clientFactory ?? http.Client.new;

  static const assetPath = 'assets/data/season_dataset.json';
  static const seasonYear = '2026';
  final AssetBundle _bundle;
  final SeasonCache _cache;
  final http.Client Function() _clientFactory;
  final String remoteUrl;
  final Duration requestTimeout;
  DataStatus _status = DataStatus.loading;
  AppData? _data;
  String? _error;
  String? _notice;
  SeasonSource? _source;
  Future<void>? _loading;
  bool _disposed = false;

  // URL별로 분리해 제공처 변경 후 다른 제공처의 캐시를 사용하지 않는다.
  String get cacheKey => 'kbo.season.$seasonYear.rules2.$remoteUrl';
  DataStatus get status => _status;
  AppData? get data => _data;
  String? get error => _error;
  String? get notice => _notice;
  SeasonSource? get source => _source;
  bool get canRetry => remoteUrl.isNotEmpty && _source != SeasonSource.network;

  Future<void> load() {
    if (_disposed) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<AppData> _parse(String source) async {
    final parsed = await compute(AppData.parse, source);
    if (parsed.year != seasonYear || parsed.teams.length != 10) {
      throw const FormatException('2026 KBO 10개 팀 시즌 데이터가 아닙니다');
    }
    return parsed;
  }

  Future<void> _load() async {
    _status = DataStatus.loading;
    _data = null;
    _error = null;
    _notice = null;
    _source = null;
    _notify();
    try {
      if (remoteUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(remoteUrl);
          if (uri.scheme != 'https' ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            throw const FormatException('시즌 데이터 주소는 HTTPS여야 합니다');
          }
          final client = _clientFactory();
          late String raw;
          try {
            final response = await client.get(uri).timeout(requestTimeout);
            if (response.statusCode != 200) {
              throw http.ClientException('HTTP ${response.statusCode}', uri);
            }
            raw = utf8.decode(response.bodyBytes);
          } finally {
            client.close();
          }
          final parsed = await _parse(raw);
          // 계약 검사에 통과한 데이터만 기존 캐시를 교체한다.
          try {
            await _cache.write(cacheKey, raw);
          } catch (_) {
            _notice = '시즌 기록을 받았지만 기기에 보관하지 못했습니다.';
          }
          _data = parsed;
          _source = SeasonSource.network;
          return;
        } catch (_) {
          _notice = '최신 시즌 기록을 받지 못했습니다.';
        }
      }

      try {
        final cached = await _cache.read(cacheKey);
        if (cached != null) {
          _data = await _parse(cached);
          _source = SeasonSource.cache;
          if (remoteUrl.isNotEmpty) {
            _notice = '최신 시즌 기록을 받지 못해 기기에 보관한 기록을 사용합니다.';
          }
          return;
        }
      } catch (_) {
        // 손상됐거나 예전 규칙의 캐시는 사용하지 않고 번들을 검증한다.
      }

      final raw = await _bundle.loadString(assetPath, cache: false);
      _data = await _parse(raw);
      _source = SeasonSource.bundled;
      if (remoteUrl.isNotEmpty) {
        _notice = '최신 시즌 기록을 받지 못해 앱에 포함된 기록을 사용합니다.';
      }
      try {
        await _cache.write(cacheKey, raw);
      } catch (_) {
        _notice ??= '시즌 기록을 기기에 보관하지 못했습니다. 포함된 기록으로 경기를 시작할 수 있습니다.';
      }
    } on FormatException {
      _error = '사용할 수 있는 시즌 데이터가 없습니다. 데이터 형식을 확인한 뒤 다시 불러와 주세요.';
    } catch (_) {
      _error = '시즌 데이터를 읽지 못했습니다. 연결 상태를 확인한 뒤 다시 불러와 주세요.';
    } finally {
      _status = _data == null ? DataStatus.failed : DataStatus.ready;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
