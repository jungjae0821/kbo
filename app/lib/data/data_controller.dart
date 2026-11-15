import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_data.dart';

enum DataStatus { loading, ready, failed }

/// 시즌 데이터 준비 상태. 지금은 앱에 묶인 시즌 JSON을 읽고 계약을 검사한다.
/// 원격 갱신과 기기 캐시가 붙으면 [_readSource]만 바꾸면 된다.
class DataController extends ChangeNotifier {
  DataController({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/data/season_dataset.json';

  final AssetBundle _bundle;
  DataStatus _status = DataStatus.loading;
  AppData? _data;
  String? _error;

  DataStatus get status => _status;
  AppData? get data => _data;
  String? get error => _error;

  Future<void> load() async {
    _status = DataStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final source = await _readSource();
      // 1.5MB JSON 파싱과 검사는 UI 스레드 밖에서 한다 (웹은 같은 스레드).
      _data = await compute(AppData.parse, source);
      _status = DataStatus.ready;
    } on FormatException catch (e) {
      _status = DataStatus.failed;
      _error = '시즌 데이터 형식이 맞지 않습니다. (${e.message})';
    } catch (e, st) {
      debugPrint('시즌 데이터 로딩 실패: $e\n$st');
      _status = DataStatus.failed;
      _error = '시즌 데이터를 읽지 못했습니다.';
    }
    notifyListeners();
  }

  Future<String> _readSource() => _bundle.loadString(assetPath, cache: false);
}
