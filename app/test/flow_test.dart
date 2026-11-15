import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/data/data_controller.dart';
import 'package:kbo_app/main.dart';
import 'package:kbo_app/state/record_book.dart';

/// 테스트에서 번들 대신 실제 시즌 JSON을 돌려준다.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }
}

void main() {
  testWidgets('팀 선택 → 예측 확정 → 경기 끝까지 → 결과 → 채점 1회', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final data = DataController(bundle: _FileBundle());
    final records = RecordBook();
    await tester.runAsync(data.load);
    expect(data.status, DataStatus.ready);

    await tester.pumpWidget(KboApp(data: data, records: records));
    await tester.pumpAndSettle();

    await tester.tap(find.text('경기 시작'));
    await tester.pumpAndSettle();

    // 원정 → 홈 순서로 두 팀 선택. 이미 고른 팀은 다른 쪽에서 고를 수 없다.
    await tester.tap(find.text('KT 위즈').last);
    await tester.pumpAndSettle();
    expect(find.text('원정팀로 선택됨'), findsOneWidget);
    await tester.tap(find.text('삼성 라이온즈').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('전력 비교'));
    await tester.pumpAndSettle();

    // 예측 전에는 확정 버튼이 꺼져 있다.
    final confirm = find.widgetWithText(FilledButton, '예측 확정');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.dragUntilVisible(find.text('삼성 승리'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삼성 승리'));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('확정하고 시작'));
    await tester.pumpAndSettle();

    expect(find.text('1회초'), findsOneWidget);
    await tester.tap(find.text('다음 타석'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('끝까지'));
    await tester.pumpAndSettle();
    expect(records.predictionCount, 1);

    await tester.tap(find.text('경기 결과 보기'));
    await tester.pumpAndSettle();
    expect(find.text('이닝별 점수'), findsOneWidget);
    expect(records.predictionCount, 1);
  });
}
