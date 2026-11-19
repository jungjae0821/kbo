import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/data_controller.dart';
import 'data/local_store.dart';
import 'screens/home_screen.dart';
import 'state/record_book.dart';
import 'state/saved_game.dart';
import 'theme/kbo_theme.dart';

void main() {
  // 데이터 로딩이 runApp 전에 rootBundle을 쓰므로 바인딩을 먼저 만든다.
  WidgetsFlutterBinding.ensureInitialized();
  // 개인 기록과 중단 경기는 같은 기기 저장소를 쓴다. 읽기는 화면을 띄운 뒤 끝나도 된다.
  final store = createDeviceStore();
  runApp(KboApp(
    data: DataController()..load(),
    records: RecordBook(store: store)..load(),
    savedGame: SavedGameStore(store: store)..load(),
  ));
}

class KboApp extends StatelessWidget {
  /// [savedGame]을 주지 않으면 저장하지 않는 중단 경기 보관함을 쓴다 (테스트용).
  KboApp({super.key, required this.data, required this.records, SavedGameStore? savedGame})
      : savedGame = savedGame ?? SavedGameStore();

  final DataController data;
  final RecordBook records;
  final SavedGameStore savedGame;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      data: data,
      records: records,
      savedGame: savedGame,
      child: MaterialApp(
        title: 'KBO 가상야구',
        debugShowCheckedModeBanner: false,
        theme: buildKboTheme(Brightness.light),
        darkTheme: buildKboTheme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
