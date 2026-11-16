import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/data/data_controller.dart';
import 'package:kbo_app/main.dart';
import 'package:kbo_app/state/record_book.dart';
import 'package:kbo_app/widgets/line_score.dart';

/// 테스트에서 번들 대신 실제 시즌 JSON을 돌려준다.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }
}

/// keepAll이 넣은 WORD JOINER를 빼고 비교한다.
Finder _plain(String text) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').replaceAll('⁠', '') == text,
    );

void main() {
  testWidgets('팀 선택 → 예측 확정 → 경기 끝까지 → 결과 → 채점 1회', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920); // 360x640, 기준으로 삼는 작은 휴대폰
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

    // 경기 전 KT 선발을 바꾼다. 되돌릴 수 있는 선택이라 확인 창 없이 바로 바뀐다.
    await tester.dragUntilVisible(find.text('선발 바꾸기').first, find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선발 바꾸기').first);
    await tester.pumpAndSettle();
    expect(_plain('KT 선발투수 고르기'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
    expect(find.text('자동 선발 소형준 대신'), findsOneWidget);

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

    // 1회초는 KT 공격, 삼성(내 예측) 수비 시작이라 투수 교체를 묻는다. 스크롤 없이 화면 안에 있어야 한다.
    expect(find.text('1회초 삼성 수비 시작'), findsOneWidget);
    expect(find.text('투수 후라도, 바꿀까요?'), findsOneWidget);
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final label in ['투수 교체', '다음 타석', '다음 수비까지']) {
      final rect = tester.getRect(find.text(label));
      expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight), isTrue, reason: '$label 버튼이 화면 밖');
    }
    await tester.tap(find.text('투수 교체'));
    await tester.pumpAndSettle();
    expect(_plain('후라도 대신 던질 투수'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '투수 교체').last);
    await tester.pumpAndSettle();
    // 최근 기록에 교체 줄이 생기고, 묻는 문구는 사라진다.
    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '').contains('후라도 대신')),
      findsOneWidget,
    );
    expect(find.text('1회초 삼성 수비 시작'), findsNothing);

    // 첫 타석 뒤 기록에는 타석 번호 대신 이닝 제목이 한 번 나온다.
    await tester.tap(find.text('다음 타석'));
    await tester.pumpAndSettle();
    expect(find.text('1회초 KT 공격'), findsOneWidget);

    // 삼성 공격이 오면 대타 버튼이 같은 자리에 보인다.
    for (var i = 0; i < 30 && find.text('대타 내기').evaluate().isEmpty; i++) {
      await tester.tap(find.text('다음 타석'));
      await tester.pumpAndSettle();
    }
    expect(find.text('대타 내기'), findsOneWidget);
    // 경기 전에 고른 KT 선발이 1회말 마운드에 있다 (자동 선발 소형준이 아니다).
    expect(find.text('소형준'), findsNothing);

    // 기록 줄이 반쯤 잘리지 않는다: 보이는 기록 줄은 모두 '내 예측' 줄보다 위에서 끝난다.
    // 휴대폰, 태블릿, 넓은 화면(그라운드 왼쪽·시트 오른쪽)에서 확인한다.
    for (final size in const [Size(1080, 1920), Size(1080, 2220), Size(2304, 3072), Size(3840, 2160)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      // 기록 칸(잘라내기 영역)의 실제 아래 끝. 보이는 줄은 모두 이 안에서 끝나야 한다.
      final area = tester.getRect(find.ancestor(of: find.byType(PlateRow).first, matching: find.byType(ClipRect)).first);
      final limit = area.bottom;
      // 기록 칸은 고정 감독 줄·버튼과 겹치지 않는다.
      expect(limit <= tester.getRect(find.text('다음 타석')).top, isTrue, reason: '$size: 기록 칸이 버튼과 겹침');
      final rows = [
        ...find.byType(PlateRow).evaluate(),
        ...find.byType(HalfHeader).evaluate(),
        ...find.byType(SubstitutionRow).evaluate(),
      ];
      final plays = find.byType(PlateRow).evaluate().length + find.byType(SubstitutionRow).evaluate().length;
      expect(plays >= 3, isTrue, reason: '$size: 기록이 3줄 미만 ($plays줄)');
      for (final e in rows) {
        final rect = tester.getRect(find.byWidget(e.widget));
        expect(rect.bottom <= limit + 0.5, isTrue, reason: '$size: 기록 줄이 잘림 ($rect, 한계 $limit)');
      }
    }
    tester.view.physicalSize = const Size(1080, 1920);
    await tester.pumpAndSettle();

    // 다음 수비까지: 내 팀 수비 시작에서 멈추거나 경기가 끝난다.
    await tester.tap(find.text('다음 수비까지'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '').endsWith('수비 시작'))
              .evaluate()
              .isNotEmpty ||
          find.text('경기 결과 보기').evaluate().isNotEmpty,
      isTrue,
    );
    for (var i = 0; i < 15 && find.text('경기 결과 보기').evaluate().isEmpty; i++) {
      await tester.tap(find.text('다음 수비까지'));
      await tester.pumpAndSettle();
    }
    expect(records.predictionCount, 1);

    await tester.tap(find.text('경기 결과 보기'));
    await tester.pumpAndSettle();
    expect(find.text('이닝별 점수'), findsOneWidget);
    expect(records.predictionCount, 1);
  });
}
