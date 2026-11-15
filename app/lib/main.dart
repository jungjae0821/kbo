import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/data_controller.dart';
import 'screens/home_screen.dart';
import 'state/record_book.dart';
import 'theme/kbo_theme.dart';

void main() {
  // 데이터 로딩이 runApp 전에 rootBundle을 쓰므로 바인딩을 먼저 만든다.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KboApp(data: DataController()..load(), records: RecordBook()));
}

class KboApp extends StatelessWidget {
  const KboApp({super.key, required this.data, required this.records});

  final DataController data;
  final RecordBook records;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      data: data,
      records: records,
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
