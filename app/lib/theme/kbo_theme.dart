import 'package:flutter/material.dart';

/// DESIGN.md 「중계 자막」의 색 역할. 라이트·다크 모두 같은 이름을 쓴다.
@immutable
class KboColors extends ThemeExtension<KboColors> {
  const KboColors({
    required this.bg,
    required this.band,
    required this.bandSub,
    required this.ink,
    required this.inkSub,
    required this.stripe,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.outRed,
    required this.bandOff,
    required this.baseOff,
  });

  final Color bg;
  final Color band;
  final Color bandSub;
  final Color ink;
  final Color inkSub;
  final Color stripe;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color outRed;
  final Color bandOff;
  final Color baseOff;

  /// 띠 위 글자는 두 모드 모두 흰색 (띠 대비 12:1 이상).
  Color get onBand => Colors.white;

  static const light = KboColors(
    bg: Color(0xFFFFFFFF),
    band: Color(0xFF1F2459),
    bandSub: Color(0xFFC5C8EE),
    ink: Color(0xFF1A1C2E),
    inkSub: Color(0xFF575B72),
    stripe: Color(0xFFF2F3F9),
    accent: Color(0xFFB8175A),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFFBE7EF),
    outRed: Color(0xFFFF6B5E),
    bandOff: Color(0xFF7378BD),
    baseOff: Color(0xFF8A8EA6),
  );

  static const dark = KboColors(
    bg: Color(0xFF121428),
    band: Color(0xFF2A2F70),
    bandSub: Color(0xFFC5C8EE),
    ink: Color(0xFFECEDF7),
    inkSub: Color(0xFFA9ACC6),
    stripe: Color(0xFF1C1F3B),
    accent: Color(0xFFFF7EB0),
    onAccent: Color(0xFF2B0816),
    accentSoft: Color(0xFF3A1A33),
    outRed: Color(0xFFFF8A7E),
    bandOff: Color(0xFF8A90D0),
    baseOff: Color(0xFF6E739E),
  );

  @override
  KboColors copyWith() => this;

  @override
  KboColors lerp(ThemeExtension<KboColors>? other, double t) {
    if (other is! KboColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KboColors(
      bg: l(bg, other.bg),
      band: l(band, other.band),
      bandSub: l(bandSub, other.bandSub),
      ink: l(ink, other.ink),
      inkSub: l(inkSub, other.inkSub),
      stripe: l(stripe, other.stripe),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      outRed: l(outRed, other.outRed),
      bandOff: l(bandOff, other.bandOff),
      baseOff: l(baseOff, other.baseOff),
    );
  }
}

extension KboContext on BuildContext {
  KboColors get kbo => Theme.of(this).extension<KboColors>()!;
}

const titleFont = 'GyeonggiTitle';
const bodyFont = 'GyeonggiBatang';

/// 모양 (DESIGN.md 6절).
const rowRadius = 8.0;
const cardRadius = 10.0;
const buttonRadius = 10.0;
const sheetRadius = 16.0;

/// 상태 변화에만 쓰는 짧은 움직임 (MOTION 1).
const motion = Duration(milliseconds: 180);
const motionCurve = Curves.easeOutCubic;

ThemeData buildKboTheme(Brightness brightness) {
  final k = brightness == Brightness.dark ? KboColors.dark : KboColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: k.accent,
    onPrimary: k.onAccent,
    secondary: k.band,
    onSecondary: k.onBand,
    error: brightness == Brightness.dark ? const Color(0xFFFF8A7E) : const Color(0xFFB3261E),
    onError: brightness == Brightness.dark ? const Color(0xFF2B0816) : Colors.white,
    surface: k.bg,
    onSurface: k.ink,
    onSurfaceVariant: k.inkSub,
    surfaceContainerHighest: k.stripe,
    outline: k.baseOff,
  );

  TextStyle t(double size, FontWeight w, {double height = 1.3}) =>
      TextStyle(fontFamily: titleFont, fontSize: size, fontWeight: w, height: height, color: k.ink);
  TextStyle b(double size, {FontWeight w = FontWeight.w400, double height = 1.5}) =>
      TextStyle(fontFamily: bodyFont, fontSize: size, fontWeight: w, height: height, color: k.ink);

  final textTheme = TextTheme(
    displaySmall: t(30, FontWeight.w700, height: 1.1),
    headlineSmall: t(22, FontWeight.w700),
    titleLarge: t(20, FontWeight.w700),
    titleMedium: t(16, FontWeight.w700),
    titleSmall: t(15, FontWeight.w700),
    labelLarge: t(15, FontWeight.w700),
    labelMedium: t(12, FontWeight.w500),
    labelSmall: t(11, FontWeight.w500),
    bodyLarge: b(15),
    bodyMedium: b(14),
    bodySmall: b(12.5, height: 1.45),
  );

  final buttonShape = WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: k.bg,
    fontFamily: bodyFont,
    textTheme: textTheme,
    extensions: [k],
    splashFactory: InkRipple.splashFactory,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: k.accent,
      selectionColor: k.accent.withValues(alpha: 0.25),
      selectionHandleColor: k.accent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 56)),
        shape: buttonShape,
        textStyle: WidgetStatePropertyAll(t(17, FontWeight.w700)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? k.stripe : k.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? k.inkSub : k.onAccent,
        ),
        mouseCursor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        shape: buttonShape,
        textStyle: WidgetStatePropertyAll(t(15, FontWeight.w700)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? k.inkSub : (brightness == Brightness.dark ? k.accent : k.band),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(48, 48)), shape: buttonShape),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sheetRadius)),
      titleTextStyle: t(18, FontWeight.w700),
      contentTextStyle: b(14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: k.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius))),
      dragHandleColor: k.baseOff,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: k.ink,
      unselectedLabelColor: k.inkSub,
      labelStyle: t(15, FontWeight.w700),
      unselectedLabelStyle: t(15, FontWeight.w500),
      indicatorColor: k.accent,
      dividerHeight: 0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: k.accent, linearTrackColor: k.stripe),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: k.band,
      contentTextStyle: b(14).copyWith(color: k.onBand),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 띠 색 보조 버튼 (이어하기, 투수 교체 등 주 버튼보다 한 단계 낮은 행동).
ButtonStyle bandButtonStyle(BuildContext context, {double height = 48}) {
  final k = context.kbo;
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(64, height)),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: titleFont, fontSize: 15, fontWeight: FontWeight.w700)),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? k.stripe : k.band,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? k.inkSub : k.onBand,
    ),
  );
}
