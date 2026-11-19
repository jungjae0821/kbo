import 'package:flutter/widgets.dart';

import 'data/data_controller.dart';
import 'state/record_book.dart';
import 'state/saved_game.dart';

/// 앱 전체가 함께 쓰는 데이터 준비 상태, 개인 기록, 중단된 경기.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.data,
    required this.records,
    required this.savedGame,
    required super.child,
  });

  final DataController data;
  final RecordBook records;
  final SavedGameStore savedGame;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      data != oldWidget.data || records != oldWidget.records || savedGame != oldWidget.savedGame;
}
