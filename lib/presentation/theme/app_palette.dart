import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.x contrast helpers.
class Contrast {
  Contrast._();

  /// AA for normal text.
  static const aa = 4.5;

  /// AA for large text (18pt+, or 14pt bold) and UI parts like icons.
  static const aaLarge = 3.0;

  static double ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Black or white, whichever reads better on [background].
  static Color bestOn(Color background) =>
      ratio(background, Colors.white) >= ratio(background, const Color(0xFF111111)) ? Colors.white : const Color(0xFF111111);

  /// Moves [color]'s lightness away from [against] until it reaches [target].
  static Color ensure(Color color, Color against, {double target = aa}) {
    if (ratio(color, against) >= target) return color;
    final darken = against.computeLuminance() > 0.4;
    var hsl = HSLColor.fromColor(color);
    for (var i = 0; i < 100 && ratio(hsl.toColor(), against) < target; i++) {
      final l = (hsl.lightness + (darken ? -0.01 : 0.01)).clamp(0.0, 1.0).toDouble();
      hsl = hsl.withLightness(l);
    }
    return hsl.toColor();
  }
}

/// The colors of one theme, split 60 / 30 / 10:
///
///  * **main (60%)**: screen backgrounds, app bars, the canvas.
///  * **second (30%)**: cards, containers, sheets, inputs, chips.
///  * **accent (10%)**: buttons, the FAB, highlights, key numbers.
///
/// Every `on*` color is checked to reach WCAG AA (4.5:1) on its background
/// (see test/presentation/theme_contrast_test.dart).
@immutable
class ThemeTokens {
  const ThemeTokens({
    required this.brightness,
    required this.main,
    required this.onMain,
    required this.onMainMuted,
    required this.second,
    required this.secondHigh,
    required this.onSecond,
    required this.onSecondMuted,
    required this.accent,
    required this.onAccent,
    required this.accentOnSecond,
    required this.outline,
    required this.success,
    required this.warning,
    required this.danger,
    required this.scrim,
  });

  final Brightness brightness;

  /// 60%: backgrounds.
  final Color main;
  final Color onMain;

  /// Secondary text on [main] (labels, captions). Still AA.
  final Color onMainMuted;

  /// 30%: cards and containers.
  final Color second;

  /// A step up from [second]: inputs, selected chips, progress tracks.
  final Color secondHigh;
  final Color onSecond;
  final Color onSecondMuted;

  /// 10%: the loud color.
  final Color accent;
  final Color onAccent;

  /// The accent tuned to stay readable as text on [second] (key numbers).
  final Color accentOnSecond;
  final Color outline;

  /// Status colors, AA on [second] (they're used on cards).
  final Color success;
  final Color warning;
  final Color danger;

  /// Behind dialogs and sheets: dims everything else so there is one focus.
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;
}

/// A named theme: one set of tokens for light mode and one for dark mode.
@immutable
class AppPalette {
  const AppPalette({required this.id, required this.name, required this.seed, required this.light, required this.dark});

  /// Stored in settings (`accent_color`) as the seed's ARGB value.
  final int id;
  final String name;

  /// Shown in the picker.
  final Color seed;
  final ThemeTokens light;
  final ThemeTokens dark;

  ThemeTokens tokens(Brightness b) => b == Brightness.dark ? dark : light;
}

class AppPalettes {
  AppPalettes._();

  // Dark mode of the default theme, as specified:
  // midnight black 60%, electric blue 30%, sunset orange 10%.
  static const midnightBlack = Color(0xFF0A0D14);
  static const electricBlue = Color(0xFF1B3A8F);
  static const electricBlueHigh = Color(0xFF2650C2);
  static const sunsetOrange = Color(0xFFFF6B35);

  static final midnight = AppPalette(
    id: 0xFFFF6B35,
    name: 'Midnight',
    seed: sunsetOrange,
    dark: _finish(
      brightness: Brightness.dark,
      main: midnightBlack,
      onMain: const Color(0xFFF2F5FB),
      onMainMuted: const Color(0xFFA8B3C7),
      second: electricBlue,
      secondHigh: electricBlueHigh,
      onSecond: const Color(0xFFF2F6FF),
      onSecondMuted: const Color(0xFFC9D6F5),
      accent: sunsetOrange,
    ),
    light: _finish(
      brightness: Brightness.light,
      main: const Color(0xFFF7F8FC),
      onMain: const Color(0xFF0B1324),
      onMainMuted: const Color(0xFF4A5468),
      second: const Color(0xFFE4ECFF),
      secondHigh: const Color(0xFFD3E0FF),
      onSecond: const Color(0xFF0B1B44),
      onSecondMuted: const Color(0xFF34436A),
      // Sunset orange, deepened so white button text passes AA.
      accent: const Color(0xFFC2410C),
    ),
  );

  /// Same 60/30/10 structure for every other accent: a near-neutral main
  /// tinted with the hue, a stronger tint of the hue for containers, and
  /// the accent itself as the loud 10%.
  static AppPalette fromSeed(String name, Color seed) {
    final hue = HSLColor.fromColor(seed).hue;
    Color hsl(double s, double l) => HSLColor.fromAHSL(1, hue, s, l).toColor();
    return AppPalette(
      id: seed.toARGB32(),
      name: name,
      seed: seed,
      light: _finish(
        brightness: Brightness.light,
        main: hsl(0.30, 0.975),
        onMain: hsl(0.30, 0.10),
        onMainMuted: hsl(0.12, 0.36),
        second: hsl(0.55, 0.92),
        secondHigh: hsl(0.55, 0.87),
        onSecond: hsl(0.60, 0.14),
        onSecondMuted: hsl(0.25, 0.32),
        accent: seed,
      ),
      dark: _finish(
        brightness: Brightness.dark,
        main: hsl(0.30, 0.055),
        onMain: hsl(0.20, 0.95),
        onMainMuted: hsl(0.12, 0.72),
        second: hsl(0.45, 0.17),
        secondHigh: hsl(0.45, 0.24),
        onSecond: hsl(0.45, 0.94),
        onSecondMuted: hsl(0.25, 0.78),
        accent: _bright(seed),
      ),
    );
  }

  static Color _bright(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness(math.max(hsl.lightness, 0.62)).toColor();
  }

  /// Fills in derived colors and nudges everything to AA.
  static ThemeTokens _finish({
    required Brightness brightness,
    required Color main,
    required Color onMain,
    required Color onMainMuted,
    required Color second,
    required Color secondHigh,
    required Color onSecond,
    required Color onSecondMuted,
    required Color accent,
  }) {
    final dark = brightness == Brightness.dark;
    // The accent fills buttons: it needs AA for its label, and must stand
    // out from the background as a UI part (3:1).
    var a = Contrast.ensure(accent, main, target: Contrast.aaLarge);
    var onA = Contrast.bestOn(a);
    if (Contrast.ratio(onA, a) < Contrast.aa) {
      a = Contrast.ensure(a, onA, target: Contrast.aa);
      onA = Contrast.bestOn(a);
    }
    final success = dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    final warning = dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    final danger = dark ? const Color(0xFFFF8A80) : const Color(0xFFB91C1C);
    return ThemeTokens(
      brightness: brightness,
      main: main,
      // Body text sits on the background and on cards, so it must pass on all three.
      onMain: _ensureAll(onMain, [main, second, secondHigh]),
      onMainMuted: _ensureAll(onMainMuted, [main, second, secondHigh]),
      second: second,
      secondHigh: secondHigh,
      onSecond: _ensureAll(onSecond, [second, secondHigh]),
      onSecondMuted: _ensureAll(onSecondMuted, [second, secondHigh]),
      accent: a,
      onAccent: onA,
      accentOnSecond: _ensureAll(a, [second, secondHigh]),
      outline: Color.alphaBlend(onMain.withValues(alpha: 0.16), main),
      success: Contrast.ensure(success, second),
      warning: Contrast.ensure(warning, second),
      danger: Contrast.ensure(danger, second),
      scrim: Colors.black.withValues(alpha: dark ? 0.66 : 0.5),
    );
  }

  static Color _ensureAll(Color c, List<Color> backgrounds) {
    var out = c;
    // Backgrounds of one theme are all light or all dark, so each pass only
    // moves further from them; a second round settles any interaction.
    for (var round = 0; round < 2; round++) {
      for (final bg in backgrounds) {
        out = Contrast.ensure(out, bg);
      }
    }
    return out;
  }

  static final all = <AppPalette>[
    midnight,
    fromSeed('Indigo', const Color(0xFF4F46E5)),
    fromSeed('Teal', const Color(0xFF0D9488)),
    fromSeed('Emerald', const Color(0xFF059669)),
    fromSeed('Sky', const Color(0xFF0284C7)),
    fromSeed('Violet', const Color(0xFF7C3AED)),
    fromSeed('Pink', const Color(0xFFDB2777)),
    fromSeed('Rose', const Color(0xFFE11D48)),
    fromSeed('Orange', const Color(0xFFEA580C)),
    fromSeed('Amber', const Color(0xFFCA8A04)),
    fromSeed('Slate', const Color(0xFF475569)),
  ];

  /// The palette saved in settings. A custom color gets its own palette
  /// with the same 60/30/10 structure; nothing saved = Midnight.
  static AppPalette byId(int? id) {
    if (id == null) return midnight;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return _custom[id] ??= fromSeed('Custom', Color(id));
  }

  static final _custom = <int, AppPalette>{};
}

/// Tokens available from any widget: `context.tokens.accent`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors(this.tokens);
  final ThemeTokens tokens;

  @override
  AppColors copyWith({ThemeTokens? tokens}) => AppColors(tokens ?? this.tokens);

  @override
  AppColors lerp(covariant AppColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension AppColorsX on BuildContext {
  /// Falls back to the default (Midnight) palette for the current
  /// brightness when the theme wasn't built by AppTheme (e.g. a plain
  /// MaterialApp in a widget test), instead of crashing.
  ThemeTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<AppColors>()?.tokens ?? AppPalettes.midnight.tokens(theme.brightness);
  }
}
