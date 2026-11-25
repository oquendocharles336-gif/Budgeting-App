import 'package:material_ui/material_ui.dart';

import 'app_palette.dart';
import 'glass.dart';

/// Visual style: frosted glass cards on a soft gradient background
/// (glassmorphism, see glass.dart), generous 16-20px spacing and a clear
/// type hierarchy, built on Material 3.
///
/// All colors come from [ThemeTokens] (see app_palette.dart), split
/// 60 / 30 / 10: main (backgrounds) / second (cards, containers) /
/// accent (buttons, highlights, key numbers). Screens read colors from the
/// [ColorScheme] or `context.tokens`, never hard-coded values.
class AppTheme {
  AppTheme._();

  static const radius = 20.0;
  static const gap = 16.0;

  /// Swatches for the theme picker (one per palette).
  static List<Color> get accentPalette => [for (final p in AppPalettes.all) p.seed];

  /// [accent] is the saved palette's seed color (settings `accent_color`).
  static ThemeData light(Color accent) => _build(AppPalettes.byId(accent.toARGB32()).light);
  static ThemeData dark(Color accent) => _build(AppPalettes.byId(accent.toARGB32()).dark);

  static ThemeData _build(ThemeTokens t) {
    final isDark = t.isDark;
    // Seeded scheme only for the few roles not covered by the tokens
    // (tertiary, inverse colors); everything visible is mapped below.
    final seeded = ColorScheme.fromSeed(seedColor: t.accent, brightness: t.brightness);
    final scheme = seeded.copyWith(
      // 10%: loud.
      primary: t.accent,
      onPrimary: t.onAccent,
      // 30%: containers.
      primaryContainer: t.secondHigh,
      onPrimaryContainer: t.onSecond,
      secondary: t.secondHigh,
      onSecondary: t.onSecond,
      secondaryContainer: t.second,
      onSecondaryContainer: t.onSecond,
      surfaceContainerLowest: t.second,
      surfaceContainerLow: t.second,
      surfaceContainer: t.second,
      surfaceContainerHigh: t.secondHigh,
      surfaceContainerHighest: t.secondHigh,
      // 60%: background.
      surface: t.main,
      onSurface: t.onMain,
      onSurfaceVariant: t.onMainMuted,
      outline: t.onMainMuted,
      outlineVariant: t.outline,
      error: t.danger,
      onError: Contrast.bestOn(t.danger),
      errorContainer: Color.alphaBlend(t.danger.withValues(alpha: 0.16), t.second),
      onErrorContainer: t.onSecond,
      scrim: t.scrim,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      extensions: [AppColors(t)],
    );
    final text = base.textTheme.apply(bodyColor: t.onMain, displayColor: t.onMain);

    final glassFill = Glass.fill(t);
    final glassShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: Glass.side(t));
    // Every page route paints the glass background behind its Scaffold.
    final glassPages = PageTransitionsTheme(builders: {
      for (final p in TargetPlatform.values) p: const GlassPageTransitionsBuilder(),
    });

    return base.copyWith(
      // Transparent: the gradient comes from each page route (glass.dart).
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: t.main,
      pageTransitionsTheme: glassPages,
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 15),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: Colors.transparent,
        foregroundColor: t.onMain,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      // Plain Cards are glass too (translucent fill, light edge); AppCard
      // adds the backdrop blur and shadow.
      cardTheme: CardThemeData(
        color: glassFill,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: glassShape,
      ),
      // Cards are "second"; text on them uses onSecond via DefaultTextStyle
      // in AppCard. List tiles inside cards pick it up from here.
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: t.onMainMuted,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Glass.fill(t, strong: true),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(color: t.onSecondMuted),
        hintStyle: TextStyle(color: t.onSecondMuted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: t.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: t.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.onMain,
          side: BorderSide(color: t.outline),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        // Text buttons sit on the 60% background: the accent tuned for it.
        style: TextButton.styleFrom(foregroundColor: Contrast.ensure(t.accent, t.main)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: glassFill,
        selectedColor: t.secondHigh,
        labelStyle: TextStyle(color: t.onSecond),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
      ),
      // No global shape here: a CircleBorder would also be applied to
      // FloatingActionButton.extended and clip its icon + label into a
      // 56px circle. The round centre "+" sets its own shape in HomeShell.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        elevation: 4,
      ),
      // Bars are drawn inside GlassBar (blur + translucent fill).
      bottomAppBarTheme: const BottomAppBarThemeData(color: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: t.secondHigh,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent, linearTrackColor: t.secondHigh),
      dividerTheme: DividerThemeData(color: t.outline, space: 1),
      // Dim what's behind dialogs and sheets so there is one focus.
      dialogTheme: DialogThemeData(
        backgroundColor: t.second,
        barrierColor: t.scrim,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.second,
        modalBackgroundColor: t.second,
        modalBarrierColor: t.scrim,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(color: t.secondHigh, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? t.secondHigh : t.onMain,
        contentTextStyle: TextStyle(color: isDark ? t.onSecond : t.main),
        actionTextColor: isDark ? Contrast.ensure(t.accent, t.secondHigh) : Contrast.ensure(t.accent, t.onMain),
      ),
    );
  }

  /// Background for "hero" cards (the big number at the top). It is part
  /// of the 30%: a gentle gradient inside the container color, with the
  /// key number in the accent ([ThemeTokens.accentOnSecond]).
  static LinearGradient heroGradient(ColorScheme scheme) => LinearGradient(
        colors: [scheme.secondaryContainer, scheme.primaryContainer],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

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
