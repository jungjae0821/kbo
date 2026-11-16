import 'package:flutter/material.dart';

/// DESIGN.md 1절의 색 토큰. 그라운드 층은 라이트·다크 모두 같은 값을 쓴다.
@immutable
class KboColors extends ThemeExtension<KboColors> {
  const KboColors({
    required this.grass,
    required this.grassDeep,
    required this.clay,
    required this.clayDeep,
    required this.chalk,
    required this.chalkSub,
    required this.sheet,
    required this.sheetRaised,
    required this.fill,
    required this.ink,
    required this.inkSub,
    required this.line,
    required this.accentText,
    this.outRed = const Color(0xFFFF5A4E),
    this.board = const Color(0xFF14201A),
  });

  final Color grass;
  final Color grassDeep;
  final Color clay;
  final Color clayDeep;
  final Color chalk;
  final Color chalkSub;
  final Color sheet;
  final Color sheetRaised;
  final Color fill;
  final Color ink;
  final Color inkSub;
  final Color line;

  /// 시트 위에서 현재 이닝·강조 숫자에 쓰는 흙색 글자.
  final Color accentText;

  /// 아웃 카운트 빨강. 잔디 위 대비가 낮아(2.3:1) 항상 [board] 위에 둔다 (5.45:1).
  final Color outRed;

  /// 아웃 카운트를 받치는 전광판 면.
  final Color board;

  static const light = KboColors(
    grass: Color(0xFF2C6440),
    grassDeep: Color(0xFF24563A),
    clay: Color(0xFFB65C33),
    clayDeep: Color(0xFF8F4524),
    chalk: Color(0xFFF6F6F1),
    chalkSub: Color(0xFFCFE0D3),
    sheet: Color(0xFFF4F5F1),
    sheetRaised: Color(0xFFFFFFFF),
    fill: Color(0xFFE6E9E3),
    ink: Color(0xFF1B211C),
    inkSub: Color(0xFF535C55),
    line: Color(0xFFDFE3DC),
    accentText: Color(0xFF8F4524),
  );

  static const dark = KboColors(
    grass: Color(0xFF2C6440),
    grassDeep: Color(0xFF24563A),
    clay: Color(0xFFB65C33),
    clayDeep: Color(0xFF8F4524),
    chalk: Color(0xFFF6F6F1),
    chalkSub: Color(0xFFCFE0D3),
    sheet: Color(0xFF141915),
    sheetRaised: Color(0xFF1C221D),
    fill: Color(0xFF283029),
    ink: Color(0xFFEEF1EC),
    inkSub: Color(0xFFA7B0A8),
    line: Color(0xFF2E3630),
    accentText: Color(0xFFE08A5F),
  );

  @override
  KboColors copyWith() => this;

  @override
  KboColors lerp(ThemeExtension<KboColors>? other, double t) {
    if (other is! KboColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KboColors(
      grass: l(grass, other.grass),
      grassDeep: l(grassDeep, other.grassDeep),
      clay: l(clay, other.clay),
      clayDeep: l(clayDeep, other.clayDeep),
      chalk: l(chalk, other.chalk),
      chalkSub: l(chalkSub, other.chalkSub),
      sheet: l(sheet, other.sheet),
      sheetRaised: l(sheetRaised, other.sheetRaised),
      fill: l(fill, other.fill),
      ink: l(ink, other.ink),
      inkSub: l(inkSub, other.inkSub),
      line: l(line, other.line),
      accentText: l(accentText, other.accentText),
      outRed: l(outRed, other.outRed),
      board: l(board, other.board),
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

ThemeData buildKboTheme(Brightness brightness) {
  final k = brightness == Brightness.light ? KboColors.light : KboColors.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: k.clay,
    onPrimary: Colors.white,
    secondary: k.grass,
    onSecondary: k.chalk,
    tertiary: k.grassDeep,
    onTertiary: k.chalk,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: k.sheet,
    onSurface: k.ink,
    onSurfaceVariant: k.inkSub,
    surfaceContainerLowest: k.sheet,
    surfaceContainerLow: k.sheetRaised,
    surfaceContainer: k.sheetRaised,
    surfaceContainerHigh: k.fill,
    surfaceContainerHighest: k.fill,
    outline: k.inkSub,
    outlineVariant: k.line,
  );

  TextStyle t(double size, FontWeight w, {double height = 1.35, Color? c}) =>
      TextStyle(
        fontFamily: titleFont,
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: size * -0.02,
        color: c,
      );
  TextStyle b(double size, FontWeight w, {double height = 1.6}) =>
      TextStyle(fontFamily: bodyFont, fontSize: size, fontWeight: w, height: height);

  final textTheme = TextTheme(
    displaySmall: t(52, FontWeight.w700, height: 1.0),
    headlineSmall: t(22, FontWeight.w700),
    titleLarge: t(20, FontWeight.w700),
    titleMedium: t(18, FontWeight.w700),
    titleSmall: t(15, FontWeight.w500),
    labelLarge: t(17, FontWeight.w700, height: 1.2),
    labelMedium: t(15, FontWeight.w500, height: 1.2),
    bodyLarge: b(15, FontWeight.w400),
    bodyMedium: b(14, FontWeight.w400),
    bodySmall: b(12, FontWeight.w400, height: 1.5),
  ).apply(bodyColor: k.ink, displayColor: k.ink);

  const pill = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: k.sheet,
    fontFamily: bodyFont,
    textTheme: textTheme,
    extensions: [k],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: k.grass,
      foregroundColor: k.chalk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t(17, FontWeight.w500, c: k.chalk),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: k.clay,
        foregroundColor: Colors.white,
        disabledBackgroundColor: k.fill,
        disabledForegroundColor: k.inkSub,
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: pill,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: k.ink,
        minimumSize: const Size(64, 48),
        shape: pill,
        textStyle: textTheme.labelMedium,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: k.sheetRaised,
        foregroundColor: k.ink,
        selectedBackgroundColor: k.grass,
        selectedForegroundColor: k.chalk,
        side: BorderSide.none,
        minimumSize: const Size(64, 52),
        shape: pill,
        textStyle: textTheme.labelMedium,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.sheetRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: k.ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: k.sheet),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: k.chalk),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// 보조 행동 버튼: fill 면, 알약형.
ButtonStyle secondaryButtonStyle(BuildContext context) {
  final k = context.kbo;
  return FilledButton.styleFrom(
    backgroundColor: k.fill,
    foregroundColor: k.ink,
    minimumSize: const Size(64, 54),
    padding: const EdgeInsets.symmetric(horizontal: 22),
    shape: const StadiumBorder(),
    textStyle: Theme.of(context).textTheme.labelMedium,
  );
}
