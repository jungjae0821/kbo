import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/theme/kbo_theme.dart';
import 'package:kbo_app/widgets/diamond.dart';

/// 만루에서 주자·타자·투수 이름표가 서로 겹치거나 다이아몬드 칸 밖으로 나가지 않는다.
/// 긴 이름(외국인 선수)과 긴 기록 문구를 넣어 가장 나쁜 경우를 본다.
void main() {
  const cases = [
    // (칸 폭, 반대각, 작은 화면)
    (200.0, 56.0, true),
    (184.0, 48.0, true),
    (192.0, 52.0, true),
    (328.0, 64.0, false),
    (328.0, 81.0, false),
    (380.0, 104.0, false),
  ];
  for (final (width, d, compact) in cases) {
    testWidgets('이름표가 겹치지 않음: 폭 $width, 반대각 $d, compact $compact', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildKboTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Diamond(
                runners: const [
                  FieldTag('1', '레이예스'),
                  FieldTag('2', '오스틴'),
                  FieldTag('3', '데이비슨'),
                ],
                outs: 2,
                batter: const FieldTag('b', '김지찬', '9번 .282'),
                pitcher: FieldTag('p', '톨허스트', compact ? '자책 4.24' : '평균자책 4.24'),
                halfDiagonal: d,
                compact: compact,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final area = tester.getRect(find.byType(Diamond));
      final tags = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_NameTag');
      expect(tags, findsNWidgets(5));
      final rects = [for (final e in tags.evaluate()) tester.getRect(find.byWidget(e.widget))];
      for (var i = 0; i < rects.length; i++) {
        // 좌우는 칸 안, 위아래는 다이아몬드 높이 안.
        expect(rects[i].left >= area.left - 0.5 && rects[i].right <= area.right + 0.5, isTrue,
            reason: '이름표 ${rects[i]}가 칸 $area 밖');
        expect(rects[i].top >= area.top - 0.5 && rects[i].bottom <= area.bottom + 0.5, isTrue,
            reason: '이름표 ${rects[i]}가 칸 $area 위아래 밖');
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse, reason: '겹침 ${rects[i]} / ${rects[j]}');
        }
      }
    });
  }
}
