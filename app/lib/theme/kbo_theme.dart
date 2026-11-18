import 'package:flutter/material.dart';

/// DESIGN.md 1절의 색 토큰 (「문자중계」 방향).
@immutable
class KboColors extends ThemeExtension<KboColors> {
  const KboColors({
    required this.bg,
    required this.surface,
    required this.soft,
    required this.fill,
    required this.ink,
    required this.inkSub,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.status,
    required this.onStatus,
    required this.statusSub,
    required this.statusOff,
    required this.baseOff,
    this.outRed = const Color(0xFFFF6B5E),
  });

  /// 화면 바탕.
  final Color bg;

  /// 메시지·목록 면.
  final Color surface;

  /// 점수가 난 메시지, 고른 항목처럼 한 단계 강조한 면.
  final Color soft;

  /// 보조 버튼 면.
  final Color fill;
  final Color ink;
  final Color inkSub;

  /// 표 행 구분이 꼭 필요한 곳의 한 겹 선.
  final Color line;

  /// 주 행동(코발트). 화면당 주 버튼 하나와 고른 항목에만.
  final Color accent;
  final Color onAccent;

  /// 바탕·면 위의 강조 글자 (현재 이닝, 득점).
  final Color accentText;

  /// 위쪽 상태 띠 면 (점수·이닝·아웃).
  final Color status;
  final Color onStatus;
  final Color statusSub;

  /// 상태 띠 위 꺼진 아웃 점.
  final Color statusOff;

  /// 면 위 비어 있는 베이스.
  final Color baseOff;

  /// 아웃 점. 항상 [status] 면 위에 둔다.
  final Color outRed;

  static const light = KboColors(
    bg: Color(0xFFF2F3F7),
    surface: Color(0xFFFFFFFF),
    soft: Color(0xFFE4E9FA),
    fill: Color(0xFFDDE0E9),
    ink: Color(0xFF161A2B),
    inkSub: Color(0xFF565C70),
    line: Color(0xFFE1E3EA),
    accent: Color(0xFF2546C8),
    onAccent: Color(0xFFFFFFFF),
    accentText: Color(0xFF2546C8),
    status: Color(0xFF161A2B),
    onStatus: Color(0xFFFFFFFF),
    statusSub: Color(0xFFC9CEDD),
    statusOff: Color(0xFF6B7391),
    baseOff: Color(0xFF8D94A8),
  );

  static const dark = KboColors(
    bg: Color(0xFF10131F),
    surface: Color(0xFF1B1F2E),
    soft: Color(0xFF24305A),
    fill: Color(0xFF2A2F42),
    ink: Color(0xFFECEEF5),
    inkSub: Color(0xFFA6ACBF),
    line: Color(0xFF2C3145),
    accent: Color(0xFF7C95FF),
    onAccent: Color(0xFF10131F),
    accentText: Color(0xFF9DB0FF),
    status: Color(0xFF272C42),
    onStatus: Color(0xFFFFFFFF),
    statusSub: Color(0xFFC9CEDD),
    statusOff: Color(0xFF7A82A0),
    baseOff: Color(0xFF6B7391),
  );

  @override
  KboColors copyWith() => this;

  @override
  KboColors lerp(ThemeExtension<KboColors>? other, double t) {
    if (other is! KboColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KboColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      soft: l(soft, other.soft),
      fill: l(fill, other.fill),
      ink: l(ink, other.ink),
      inkSub: l(inkSub, other.inkSub),
      line: l(line, other.line),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentText: l(accentText, other.accentText),
      status: l(status, other.status),
      onStatus: l(onStatus, other.onStatus),
      statusSub: l(statusSub, other.statusSub),
      statusOff: l(statusOff, other.statusOff),
      baseOff: l(baseOff, other.baseOff),
      outRed: l(outRed, other.outRed),
    );
  }
}

extension KboThemeContext on BuildContext {
  KboColors get kbo => Theme.of(this).extension<KboColors>()!;
}

/// 제목·버튼은 경기천년제목, 본문·표는 경기천년바탕.
const titleFont = 'GyeonggiTitle';
const bodyFont = 'GyeonggiBatang';

/// DESIGN.md 5절: 모든 전환은 한 가지 길이와 곡선.
const motion = Duration(milliseconds: 200);
const motionCurve = Curves.easeOutCubic;

/// DESIGN.md 3절 반경. 버튼 16, 메시지·목록 16, 상태 띠 20.
const buttonRadius = 16.0;
const bubbleRadius = 16.0;
const statusRadius = 20.0;

const _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(buttonRadius)));

ThemeData buildKboTheme(Brightness brightness) {
  final k = brightness == Brightness.light ? KboColors.light : KboColors.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: k.accent,
    onPrimary: k.onAccent,
    secondary: k.status,
    onSecondary: k.onStatus,
    tertiary: k.soft,
    onTertiary: k.ink,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: k.bg,
    onSurface: k.ink,
    onSurfaceVariant: k.inkSub,
    surfaceContainerLowest: k.bg,
    surfaceContainerLow: k.surface,
    surfaceContainer: k.surface,
    surfaceContainerHigh: k.fill,
    surfaceContainerHighest: k.fill,
    outline: k.inkSub,
    outlineVariant: k.line,
  );

  TextStyle t(double size, FontWeight w, {double height = 1.35, Color? c}) => TextStyle(
        fontFamily: titleFont,
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: size * -0.02,
        color: c,
      );
  TextStyle b(double size, FontWeight w, {double height = 1.55}) =>
      TextStyle(fontFamily: bodyFont, fontSize: size, fontWeight: w, height: height);

  final textTheme = TextTheme(
    displaySmall: t(28, FontWeight.w700, height: 1.1),
    headlineSmall: t(22, FontWeight.w700),
    titleLarge: t(20, FontWeight.w700),
    titleMedium: t(17, FontWeight.w700),
    titleSmall: t(15, FontWeight.w500),
    labelLarge: t(17, FontWeight.w700, height: 1.2),
    labelMedium: t(15, FontWeight.w500, height: 1.2),
    labelSmall: t(12, FontWeight.w500, height: 1.3),
    bodyLarge: b(15, FontWeight.w400),
    bodyMedium: b(14, FontWeight.w400),
    bodySmall: b(13, FontWeight.w400, height: 1.5),
  ).apply(bodyColor: k.ink, displayColor: k.ink);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: k.bg,
    fontFamily: bodyFont,
    textTheme: textTheme,
    extensions: [k],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: k.bg,
      foregroundColor: k.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t(20, FontWeight.w700, c: k.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: k.accent,
        foregroundColor: k.onAccent,
        disabledBackgroundColor: k.fill,
        disabledForegroundColor: k.inkSub,
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: _buttonShape,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: k.ink,
        minimumSize: const Size(64, 48),
        shape: _buttonShape,
        textStyle: textTheme.labelMedium,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: k.ink, minimumSize: const Size(48, 48)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(statusRadius)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: k.bg,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: k.baseOff,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: k.status,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: k.onStatus),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bubbleRadius)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: k.accent),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// 보조 행동 버튼: fill 면, 주 버튼과 같은 반경.
ButtonStyle secondaryButtonStyle(BuildContext context) {
  final k = context.kbo;
  return FilledButton.styleFrom(
    backgroundColor: k.fill,
    foregroundColor: k.ink,
    minimumSize: const Size(64, 54),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    shape: _buttonShape,
    textStyle: Theme.of(context).textTheme.labelMedium,
  );
}
