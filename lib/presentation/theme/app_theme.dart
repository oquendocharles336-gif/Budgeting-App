import 'package:flutter/material.dart';

/// Visual style: soft rounded cards on a tinted background, a bold gradient
/// "hero" card for the main number, generous 16-20px spacing and clear
/// type hierarchy. Built on Material 3 so contrast comes from the scheme.
class AppTheme {
  AppTheme._();

  static const radius = 20.0;
  static const gap = 16.0;

  static const accentPalette = <Color>[
    Color(0xFF4F46E5), // indigo
    Color(0xFF0D9488), // teal
    Color(0xFF059669), // emerald
    Color(0xFF0284C7), // sky
    Color(0xFF7C3AED), // violet
    Color(0xFFDB2777), // pink
    Color(0xFFE11D48), // rose
    Color(0xFFEA580C), // orange
    Color(0xFFCA8A04), // amber
    Color(0xFF475569), // slate
  ];

  static ThemeData light(Color accent) => _build(accent, Brightness.light);
  static ThemeData dark(Color accent) => _build(accent, Brightness.dark);

  static ThemeData _build(Color accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
    final background = isDark ? const Color(0xFF0E1014) : const Color(0xFFF4F5FA);
    final surface = isDark ? const Color(0xFF181B22) : Colors.white;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme.copyWith(surface: surface),
    );
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 15),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? const Color(0xFF22262F) : const Color(0xFFF0F1F6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const CircleBorder(),
        elevation: 4,
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Gradient for hero cards, derived from the accent.
  static LinearGradient heroGradient(ColorScheme scheme) {
    final hsl = HSLColor.fromColor(scheme.primary);
    final end = hsl.withHue((hsl.hue + 35) % 360).withLightness((hsl.lightness * 0.85).clamp(0.2, 0.6).toDouble()).toColor();
    return LinearGradient(
      colors: [scheme.primary, end],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  /// Black or white text, whichever reads better on [background].
  static Color onColor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Colors.white : Colors.black87;
}

/// Semantic colors for budget states that read well in light and dark mode.
class StatusColors {
  StatusColors._();
  static Color ok(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  static Color warning(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  static Color danger(BuildContext c) => Theme.of(c).colorScheme.error;
  static Color income(BuildContext c) => ok(c);
}
