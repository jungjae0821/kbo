import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/data/data_controller.dart';
import 'package:kbo_app/main.dart';
import 'package:kbo_app/state/record_book.dart';
import 'package:kbo_app/widgets/play_feed.dart';

/// 테스트에서 번들 대신 실제 시즌 JSON을 돌려준다.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());
}

/// keepAll이 넣은 WORD JOINER를 빼고 비교한다.
Finder _plain(String text) => find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '') == text);

Finder _contains(String text) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('⁠', '').contains(text),
    );

/// [finder]가 화면 안에 온전히 보이는가.
bool _onScreen(WidgetTester tester, Finder finder) {
  final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  final rect = tester.getRect(finder);
  return screen.contains(rect.topLeft) && screen.contains(rect.bottomRight - const Offset(0.1, 0.1));
}

void main() {
  testWidgets('메인 → 준비 4단계 → 경기 → 결과·상세보기 → 다시하기 → 처음으로', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920); // 360x640, 기준으로 삼는 작은 휴대폰
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final data = DataController(bundle: _FileBundle(), remoteUrl: '');
    final records = RecordBook();
    await tester.runAsync(data.load);
    expect(data.status, DataStatus.ready);

    await tester.pumpWidget(KboApp(data: data, records: records));
    await tester.pumpAndSettle();

    // 메인: 순위표 10개 팀과 시작 버튼이 스크롤 없이 한 화면에.
    expect(find.text('2026 정규시즌 순위'), findsOneWidget);
    expect(find.text('0.647'), findsOneWidget); // KT 승률 (90승 49패)
    expect(_onScreen(tester, find.text('키움')), isTrue, reason: '10위 줄이 화면 밖');
    expect(_onScreen(tester, find.text('시뮬레이션 시작')), isTrue);
    expect(tester.getRect(find.text('키움')).bottom <= tester.getRect(find.text('시뮬레이션 시작')).top, isTrue);

    await tester.tap(find.text('시뮬레이션 시작'));
    await tester.pumpAndSettle();

    // ① 두 팀: 원정 → 홈 순서로 채운다. 둘 다 고르기 전에는 다음으로 갈 수 없다.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '두 팀을 고르세요')).onPressed, isNull);
    await tester.tap(find.text('KT 위즈'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('원정팀으로 선택됨')), findsOneWidget);
    await tester.tap(find.text('삼성 라이온즈').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('선발투수 고르기'));
    await tester.pumpAndSettle();

    // ② 선발투수: 선발 기록이 있는 투수만 고를 수 있다. 바꾸면 자동 선발 대신이라고 보인다.
    await tester.tap(find.text('KT 선발 바꾸기'));
    await tester.pumpAndSettle();
    expect(_plain('KT 선발투수 고르기'), findsOneWidget);
    expect(_contains('선발 '), findsWidgets);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
    expect(find.text('자동 선발 소형준 대신'), findsOneWidget);
    expect(_contains('공식 시즌 표의 팀 분류입니다.'), findsOneWidget);
    await tester.tap(find.text('라인업 확인'));
    await tester.pumpAndSettle();

    // ③ 라인업: 원정 KT 9명이 보이고, 1번과 2번을 맞바꿀 수 있다.
    expect(find.text('자동 라인업'), findsOneWidget);
    final first = find.bySemanticsLabel(RegExp(r'^1번 '));
    final firstName = tester.getSemantics(first).label.split(',').first.substring(3);
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^2번 .*맞바꾸기')));
    await tester.pumpAndSettle();
    expect(find.text('바꾼 라인업'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^2번 $firstName,')), findsOneWidget);
    expect(_onScreen(tester, find.bySemanticsLabel(RegExp(r'^9번 '))), isTrue, reason: '9번 타자가 화면 밖');
    await tester.tap(find.text('승리 팀 예측'));
    await tester.pumpAndSettle();

    // ④ 예측: 고르기 전에는 시작할 수 없다.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '이길 팀을 고르세요')).onPressed, isNull);
    await tester.tap(find.text('삼성 라이온즈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삼성 승리로 경기 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확정하고 시작'));
    await tester.pumpAndSettle();

    // 경기: 1회초 KT 공격, 삼성(내 예측) 수비. 선발은 첫 타자 전이라 바꿀 수 없다.
    expect(find.text('1회초'), findsOneWidget);
    expect(find.text('삼성 수비 중'), findsOneWidget);
    expect(find.text('투수 후라도, 첫 타자 상대 전'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '투수 교체')).onPressed, isNull);
    for (final label in ['투수 교체', '다음 타석', '다음 수비까지']) {
      expect(_onScreen(tester, find.text(label)), isTrue, reason: '$label 버튼이 화면 밖');
    }

    await tester.tap(find.text('다음 타석'));
    await tester.pumpAndSettle();
    expect(find.text('1회초 KT 공격'), findsOneWidget);
    // 바꾼 타순대로 첫 타자가 나왔다 (원래 2번이 1번으로).
    expect(find.byType(PlateRow), findsOneWidget);

    // 한 타자를 상대했으니 투수를 바꿀 수 있다.
    await tester.tap(find.text('투수 교체'));
    await tester.pumpAndSettle();
    expect(_plain('후라도 대신 던질 투수'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '투수 교체').last);
    await tester.pumpAndSettle();
    expect(_contains('후라도 대신'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '투수 교체')).onPressed, isNull);

    // 기록 줄은 반쯤 잘리지 않고 버튼과 겹치지 않는다 (휴대폰, 태블릿, 넓은 화면).
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.text('다음 타석'));
      await tester.pumpAndSettle();
      if (find.text('경기 결과 보기').evaluate().isNotEmpty) break;
    }
    for (final size in const [Size(1080, 1920), Size(2304, 3072), Size(3840, 2160)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      if (find.byType(PlateRow).evaluate().isEmpty) continue;
      final area = tester.getRect(find.ancestor(of: find.byType(PlateRow).first, matching: find.byType(ClipRect)).first);
      for (final e in [...find.byType(PlateRow).evaluate(), ...find.byType(HalfHeader).evaluate()]) {
        expect(tester.getRect(find.byWidget(e.widget)).bottom <= area.bottom + 0.5, isTrue, reason: '$size: 기록 줄이 잘림');
      }
      expect(tester.takeException(), isNull, reason: '$size');
    }
    tester.view.physicalSize = const Size(1080, 1920);
    await tester.pumpAndSettle();

    for (var i = 0; i < 40 && find.text('경기 결과 보기').evaluate().isEmpty; i++) {
      await tester.tap(find.text('다음 수비까지'));
      await tester.pumpAndSettle();
    }
    expect(records.predictionCount, 1);

    // 결과: 스코어보드, 승리·패전·세이브·홀드, 상세보기·다시하기·처음으로.
    await tester.tap(find.text('경기 결과 보기'));
    await tester.pumpAndSettle();
    expect(find.text('R'), findsOneWidget);
    for (final label in ['승리', '패전', '세이브', '홀드']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    for (final label in ['상세보기', '다시하기', '처음으로']) {
      expect(_onScreen(tester, find.text(label)), isTrue, reason: '$label 버튼이 화면 밖');
    }

    await tester.tap(find.text('상세보기'));
    await tester.pumpAndSettle();
    expect(find.text('타자'), findsOneWidget);
    expect(find.text('투수'), findsOneWidget);
    expect(find.text('타점'), findsOneWidget);
    await tester.tap(find.text('홈 삼성'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();

    // 다시하기: 직전 두 팀으로 준비 화면의 선발 단계가 열린다.
    await tester.tap(find.text('다시하기'));
    await tester.pumpAndSettle();
    expect(find.text('시뮬레이션 준비'), findsOneWidget);
    expect(find.text('KT 선발 바꾸기'), findsOneWidget);
    expect(find.text('자동 선발 소형준 대신'), findsOneWidget);
    expect(records.predictionCount, 1);

    // 준비 화면에서 뒤로 두 번이면 메인.
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.text('2026 정규시즌 순위'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('결과 화면 처음으로는 메인으로 간다', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final data = DataController(bundle: _FileBundle(), remoteUrl: '');
    await tester.runAsync(data.load);
    await tester.pumpWidget(KboApp(data: data, records: RecordBook()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시뮬레이션 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LG 트윈스'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('두산 베어스'));
    await tester.pumpAndSettle();
    for (final label in ['선발투수 고르기', '라인업 확인', '승리 팀 예측']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('LG 트윈스'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LG 승리로 경기 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확정하고 시작'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 40 && find.text('경기 결과 보기').evaluate().isEmpty; i++) {
      await tester.tap(find.text('다음 수비까지'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('경기 결과 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('처음으로'));
    await tester.pumpAndSettle();
    expect(find.text('2026 정규시즌 순위'), findsOneWidget);
    expect(find.text('1경기'), findsNothing);
  });
}
