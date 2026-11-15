import 'package:flutter/widgets.dart';

import 'data/data_controller.dart';
import 'state/record_book.dart';

/// 앱 전체가 함께 쓰는 데이터 준비 상태와 개인 기록.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.data,
    required this.records,
    required super.child,
  });

  final DataController data;
  final RecordBook records;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      data != oldWidget.data || records != oldWidget.records;
}
