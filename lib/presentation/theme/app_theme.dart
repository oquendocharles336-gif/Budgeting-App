import 'package:material_ui/material_ui.dart';

import 'app_palette.dart';

/// Spacing scale (Figma "Dimensions · space").
class Space {
  Space._();
  static const xxs = 4.0;
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Side padding of every screen.
  static const screen = 16.0;
}

/// Corner radii (Figma "Dimensions · radius").
class Radii {
  Radii._();
  static const chip = 999.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const card = 18.0;
  static const hero = 22.0;
  static const sheet = 28.0;
  static const dialog = 24.0;
}

/// Motion specs from the Figma notes.
class Motion {
  Motion._();

  /// Preview / tab content cross-fade.
  static const fade = Duration(milliseconds: 200);

  /// Amount count-up on Budget.
  static const countUp = Duration(milliseconds: 450);

  /// Progress bar length + color ease (amber → green).
  static const bar = Duration(milliseconds: 600);

  /// Undo window on the "Marked paid" toast.
  static const undo = Duration(seconds: 6);

  static const curve = Curves.easeOutCubic;
}

/// The Pitaka visual style (Figma "Pitaka — Loans & Budget redesign"):
/// flat white (or navy) cards with a 1px border on a cool background,
/// one brand accent, pill-shaped buttons and tabs, Plus Jakarta Sans.
///
/// All colors come from [ThemeTokens] (app_palette.dart). Screens read
/// them from the [ColorScheme] or `context.tokens`, never hard-coded.
class AppTheme {
  AppTheme._();

  static const fontFamily = 'PlusJakartaSans';

  static const radius = Radii.card;
  static const gap = Space.lg;

  /// Swatches for the accent picker (Sunset, Teal).
  static List<Color> get accentPalette => [for (final p in AppPalettes.all) p.seed];

  /// [accent] is the saved palette's seed color (settings `accent_color`).
  static ThemeData light(Color accent) => _build(AppPalettes.byId(accent.toARGB32()).light);
  static ThemeData dark(Color accent) => _build(AppPalettes.byId(accent.toARGB32()).dark);

  /// Type scale (Figma text styles).
  static TextTheme _textTheme(TextTheme base, ThemeTokens t) {
    TextStyle? s(TextStyle? b, double size, FontWeight w, {double? height, double spacing = 0}) =>
        b?.copyWith(fontSize: size, fontWeight: w, height: height, letterSpacing: spacing, color: t.onMain);
    return base.copyWith(
      // Hero amounts (₱2,500.00).
      displaySmall: s(base.displaySmall, 34, FontWeight.w800, height: 1.15, spacing: -0.6),
      // Budget "Remaining" amount.
      headlineLarge: s(base.headlineLarge, 32, FontWeight.w800, height: 1.15, spacing: -0.5),
      // Screen titles on tabs ("Budget", "Activity").
      headlineMedium: s(base.headlineMedium, 28, FontWeight.w800, height: 1.2, spacing: -0.4),
      headlineSmall: s(base.headlineSmall, 24, FontWeight.w800, height: 1.25, spacing: -0.3),
      // Pushed screen titles ("Loans"), sheet titles.
      titleLarge: s(base.titleLarge, 22, FontWeight.w800, height: 1.25, spacing: -0.2),
      // Card titles, section headers ("Category budgets").
      titleMedium: s(base.titleMedium, 17, FontWeight.w700, height: 1.3),
      titleSmall: s(base.titleSmall, 15, FontWeight.w700, height: 1.3),
      bodyLarge: s(base.bodyLarge, 16, FontWeight.w500, height: 1.45),
      bodyMedium: s(base.bodyMedium, 14, FontWeight.w500, height: 1.45),
      bodySmall: s(base.bodySmall, 12.5, FontWeight.w500, height: 1.4)?.copyWith(color: t.onMainMuted),
      labelLarge: s(base.labelLarge, 15, FontWeight.w700, height: 1.2),
      labelMedium: s(base.labelMedium, 13, FontWeight.w600, height: 1.2),
      labelSmall: s(base.labelSmall, 12, FontWeight.w700, height: 1.2),
    );
  }

  static ThemeData _build(ThemeTokens t) {
    // Seeded scheme only for the few roles not covered by the tokens
    // (tertiary, inverse colors); everything visible is mapped below.
    final seeded = ColorScheme.fromSeed(seedColor: t.accent, brightness: t.brightness);
    final scheme = seeded.copyWith(
      primary: t.accent,
      onPrimary: t.onAccent,
      primaryContainer: t.accentContainer,
      onPrimaryContainer: t.onAccentContainer,
      secondary: t.accentOnSecond,
      onSecondary: t.second,
      secondaryContainer: t.secondHigh,
      onSecondaryContainer: t.onSecond,
      tertiary: t.success,
      tertiaryContainer: t.successContainer,
      onTertiaryContainer: t.onSuccessContainer,
      surface: t.main,
      onSurface: t.onMain,
      onSurfaceVariant: t.onMainMuted,
      surfaceContainerLowest: t.second,
      surfaceContainerLow: t.second,
      surfaceContainer: t.second,
      surfaceContainerHigh: t.secondHigh,
      surfaceContainerHighest: t.secondHigh,
      surfaceTint: Colors.transparent,
      outline: t.onMainMuted,
      outlineVariant: t.outline,
      error: t.danger,
      onError: Contrast.bestOn(t.danger),
      errorContainer: t.dangerContainer,
      onErrorContainer: t.onDangerContainer,
      inverseSurface: t.inverseSurface,
      onInverseSurface: t.onInverseSurface,
      inversePrimary: t.inverseAccent,
      scrim: t.scrim,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      extensions: [AppColors(t)],
    );
    final text = _textTheme(base.textTheme, t);

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.card),
      side: BorderSide(color: t.outline),
    );
    OutlineInputBorder field(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: color, width: width),
        );
    const pill = StadiumBorder();

    return base.copyWith(
      scaffoldBackgroundColor: t.main,
      canvasColor: t.main,
      textTheme: text,
      appBarTheme: AppBarThemeData(
        backgroundColor: t.main,
        foregroundColor: t.onMain,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: Space.screen,
        titleTextStyle: text.titleLarge,
      ),
      // Flat cards: white / navy fill and a 1px border, no shadow.
      cardTheme: CardThemeData(
        color: t.second,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
        iconColor: t.onSecondMuted,
        textColor: t.onSecond,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: t.onSecond),
        subtitleTextStyle: text.bodySmall?.copyWith(color: t.onSecondMuted),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: t.second,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
        labelStyle: TextStyle(color: t.onSecondMuted, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: t.onSecondMuted, fontWeight: FontWeight.w500),
        border: field(t.outline),
        enabledBorder: field(t.outline),
        focusedBorder: field(t.accent, 1.5),
        errorBorder: field(t.danger),
        focusedErrorBorder: field(t.danger, 1.5),
      ),
      // Figma "Button / Filled": full-width pill, 52px.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          disabledBackgroundColor: t.secondHigh,
          disabledForegroundColor: t.onSecondMuted,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: pill,
          elevation: 0,
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.onSecond,
          backgroundColor: t.second,
          side: BorderSide(color: t.outline),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      // Figma "Button / Text": accent label, no fill.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accentOnSecond,
          minimumSize: const Size(48, 48),
          shape: pill,
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: t.onMain)),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.second,
        selectedColor: t.accentContainer,
        disabledColor: t.secondHigh,
        labelStyle: TextStyle(fontFamily: fontFamily, color: t.onSecond, fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: TextStyle(fontFamily: fontFamily, color: t.onAccentContainer, fontWeight: FontWeight.w700, fontSize: 13),
        checkmarkColor: t.onAccentContainer,
        shape: StadiumBorder(side: BorderSide(color: t.outline)),
        side: BorderSide(color: t.outline),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: t.second,
          foregroundColor: t.onSecondMuted,
          selectedBackgroundColor: t.accentContainer,
          selectedForegroundColor: t.onAccentContainer,
          side: BorderSide(color: t.outline),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        elevation: 2,
        highlightElevation: 4,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(color: t.second, surfaceTintColor: Colors.transparent, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.second,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: t.accentContainer,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent, linearTrackColor: t.secondHigh),
      dividerTheme: DividerThemeData(color: t.outline, space: 1, thickness: 1),
      // Figma "Dialog": 24px radius, title 20/800, actions as pills.
      dialogTheme: DialogThemeData(
        backgroundColor: t.second,
        barrierColor: t.scrim,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.dialog)),
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 20, color: t.onSecond),
        contentTextStyle: text.bodyLarge?.copyWith(color: t.onSecond, fontWeight: FontWeight.w500),
      ),
      // Figma sheets: 28px top corners and a grab handle.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.second,
        modalBackgroundColor: t.second,
        modalBarrierColor: t.scrim,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: t.outline,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.second,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: BorderSide(color: t.outline)),
      ),
      // Figma "Toast": dark navy, rounded, accent action.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.inverseSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        contentTextStyle: TextStyle(fontFamily: fontFamily, color: t.onInverseSurface, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
        actionTextColor: t.inverseAccent,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: t.second,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: t.second,
        headerForegroundColor: t.onSecond,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.dialog)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.onAccent : t.onSecondMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : t.secondHigh),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : t.outline),
      ),
    );
  }

  /// The Figma hero gradient (Sunset: #FF6B35 → #C2410C).
  static LinearGradient heroGradient(ThemeTokens t) => t.heroGradient;

  /// Black or white text, whichever reads better on [background]. For
  /// user-picked colors (cards, categories), which aren't theme tokens.
  static Color onColor(Color background) => Contrast.bestOn(background);
}

/// Semantic status colors from the theme tokens (AA on cards).
class StatusColors {
  StatusColors._();
  static Color ok(BuildContext c) => c.tokens.success;
  static Color warning(BuildContext c) => c.tokens.warning;
  static Color danger(BuildContext c) => c.tokens.danger;
  static Color income(BuildContext c) => ok(c);
}
