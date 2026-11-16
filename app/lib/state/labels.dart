import 'package:kbo_engine/kbo_engine.dart';

String outcomeLabel(PlateOutcome o) => switch (o) {
      PlateOutcome.strikeout => '삼진',
      PlateOutcome.walk => '볼넷',
      PlateOutcome.single => '단타',
      PlateOutcome.doubleHit => '2루타',
      PlateOutcome.triple => '3루타',
      PlateOutcome.homeRun => '홈런',
      PlateOutcome.otherOut => '아웃',
    };

bool isHit(PlateOutcome o) =>
    o == PlateOutcome.single ||
    o == PlateOutcome.doubleHit ||
    o == PlateOutcome.triple ||
    o == PlateOutcome.homeRun;

String positionLabel(String code) => switch (code) {
      'C' => '포수',
      '1B' => '1루수',
      '2B' => '2루수',
      '3B' => '3루수',
      'SS' => '유격수',
      'LF' => '좌익수',
      'CF' => '중견수',
      'RF' => '우익수',
      'DH' => '지명타자',
      _ => code,
    };

String halfLabel(int inning, bool isTop) => '$inning회${isTop ? '초' : '말'}';

String endLabel(GameEnd end) => switch (end) {
      GameEnd.homeAheadAfterTop => '9회말 없이 종료',
      GameEnd.walkOff => '끝내기',
      GameEnd.regulation => '9회 종료',
      GameEnd.extraInnings => '연장 종료',
      GameEnd.tie => '12회 무승부',
    };

/// ".265"처럼 앞의 0을 뺀 타율 표기.
String avg(double? v) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(3);
  return s.startsWith('0') ? s.substring(1) : s;
}

String era(double? v) => v == null ? '—' : v.toStringAsFixed(2);

/// 주자 상태를 "1·2루", "만루", "주자 없음"으로.
String basesLabel(List<String?> bases) {
  final on = [for (var i = 0; i < 3; i++) if (bases[i] != null) i + 1];
  if (on.isEmpty) return '주자 없음';
  if (on.length == 3) return '만루';
  return '${on.join('·')}루';
}

/// 한국어 줄바꿈을 어절 단위로 (CSS word-break: keep-all과 같은 효과).
/// Flutter는 한글을 음절마다 끊을 수 있어서, 어절 안 글자 사이에 WORD JOINER(U+2060)를 넣는다.
String keepAll(String text) => text
    .split(' ')
    .map((word) => word.split('').join('\u2060'))
    .join(' ');

/// 이름 뒤 목적격 조사: 받침이 있으면 "을", 없으면 "를". 한글이 아니면 "을(를)".
String withObject(String name) {
  if (name.isEmpty) return name;
  final c = name.codeUnitAt(name.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) return '$name을(를)';
  return (c - 0xAC00) % 28 == 0 ? '$name를' : '$name을';
}

/// 전광판식 한 글자 포지션: 포수 "포", 유격수 "유", 중견수 "중", 1루수 "1".
String positionShort(String code) => switch (code) {
      'C' => '포',
      '1B' => '1',
      '2B' => '2',
      '3B' => '3',
      'SS' => '유',
      'LF' => '좌',
      'CF' => '중',
      'RF' => '우',
      'DH' => '지',
      _ => code,
    };
