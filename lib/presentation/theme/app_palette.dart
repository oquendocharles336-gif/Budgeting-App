import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

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

/// The Pitaka design tokens of one theme (Figma: "Theme · Light" /
/// "Theme · Dark" variables, combined with one "Accent" collection).
///
/// Flat surfaces on a cool off-white (or midnight) background:
///
///  * [main]: screen background.
///  * [second]: cards, sheets, dialogs, the bottom bar (white / navy),
///    with a 1px [outline] border instead of a shadow.
///  * [secondHigh]: one step up: progress tracks, skeletons, icon bubbles,
///    input fills.
///  * [accent]: the brand color (Sunset orange or Teal): filled buttons,
///    the hero card gradient, the selected tab pill.
///
/// Every text token is nudged to WCAG AA (4.5:1) on the surfaces it is used
/// on (see test/presentation/theme_contrast_test.dart). The one exception is
/// the Figma brand fill itself ([accent], [heroStart]): white labels on it
/// are bold and ≥16px, and the test documents its ratio.
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
    required this.outline,
    required this.accent,
    required this.onAccent,
    required this.accentOnSecond,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.heroStart,
    required this.heroEnd,
    required this.onHero,
    required this.onHeroMuted,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.neutralContainer,
    required this.onNeutralContainer,
    required this.infoContainer,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inverseAccent,
    required this.scrim,
  });

  final Brightness brightness;

  /// Screen background.
  final Color main;
  final Color onMain;

  /// Secondary text on [main] and on cards (labels, captions). Still AA.
  final Color onMainMuted;

  /// Cards, sheets, dialogs, bars.
  final Color second;

  /// A step up from [second]: tracks, skeletons, icon bubbles, inputs.
  final Color secondHigh;
  final Color onSecond;
  final Color onSecondMuted;

  /// Card borders and dividers (1px).
  final Color outline;

  /// Brand fill: filled buttons, the FAB, progress, focus rings.
  final Color accent;
  final Color onAccent;

  /// The accent as text on cards and on the background ("Mark unpaid",
  /// "Add", "Cancel").
  final Color accentOnSecond;

  /// Tonal fill (Figma "Button / Tonal"): the "Paid" button, the selected
  /// segment, the selected nav pill, the empty-state circle.
  final Color accentContainer;
  final Color onAccentContainer;

  /// Hero card gradient (top left → bottom right) and its text.
  final Color heroStart;
  final Color heroEnd;
  final Color onHero;
  final Color onHeroMuted;

  /// Status colors: the strong color is AA on cards (bars, amounts, icons);
  /// containers are badge / banner fills with their own AA text.
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;

  /// "Not in budget" and other neutral pills.
  final Color neutralContainer;
  final Color onNeutralContainer;

  /// The blue-grey panel used for previews ("Balance · Cash → ...").
  final Color infoContainer;

  /// Snackbars / toasts.
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inverseAccent;

  /// Behind dialogs and sheets.
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  LinearGradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [heroStart, heroEnd],
      );
}

/// A named accent (Figma "Accent" collection) with its light and dark theme.
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

/// Raw values from the Figma file ("Pitaka — Loans & Budget redesign").
class PitakaColors {
  PitakaColors._();

  // Theme · Light
  static const lightBackground = Color(0xFFF5F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFE6ECFA);
  static const lightBorder = Color(0xFFE3E8F0);
  static const lightInk = Color(0xFF0F172A);
  static const lightInkMuted = Color(0xFF5B6578);
  static const lightInfo = Color(0xFFE6EDFD);
  static const lightNeutral = Color(0xFFE2E8F2);
  static const lightOnNeutral = Color(0xFF475569);
  static const lightSuccess = Color(0xFF15803D);
  static const lightSuccessContainer = Color(0xFFDCF5E3);
  static const lightWarning = Color(0xFFB45309);
  static const lightWarningContainer = Color(0xFFFEEFD3);
  static const lightOnWarning = Color(0xFF92400E);
  static const lightDanger = Color(0xFFB91C1C);
  static const lightDangerContainer = Color(0xFFFDE2E2);
  static const lightInverse = Color(0xFF0F1428);

  // Theme · Dark
  static const darkBackground = Color(0xFF0A0E1A);
  static const darkSurface = Color(0xFF111C38);
  static const darkSurfaceHigh = Color(0xFF1A2648);
  static const darkBorder = Color(0xFF1F2B4C);
  static const darkInk = Color(0xFFF1F5F9);
  static const darkInkMuted = Color(0xFF94A3B8);
  static const darkInfo = Color(0xFF1A2648);
  static const darkNeutral = Color(0xFF22304B);
  static const darkOnNeutral = Color(0xFFCBD5E1);
  static const darkSuccess = Color(0xFF4ADE80);
  static const darkSuccessContainer = Color(0xFF12322A);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkWarningContainer = Color(0xFF3A2C16);
  static const darkOnWarning = Color(0xFFFDD58A);
  static const darkDanger = Color(0xFFFF8A80);
  static const darkDangerContainer = Color(0xFF3B1A1E);
  static const darkInverse = Color(0xFF26324F);

  // Accent · Sunset
  static const sunset = Color(0xFFFF6B35);
  static const sunsetDeep = Color(0xFFC2410C);
  static const sunsetContainer = Color(0xFFFFE1D5);
  static const sunsetOnDark = Color(0xFFFF8A5C);

  // Accent · Teal
  static const teal = Color(0xFF0D9488);
  static const tealDeep = Color(0xFF0F766E);
  static const tealContainer = Color(0xFFCCF2EE);
  static const tealOnDark = Color(0xFF5EEAD4);
}

class AppPalettes {
  AppPalettes._();

  /// The default accent's id and picker swatch (same value as before the
  /// redesign, so saved settings still match).
  static const sunsetOrange = PitakaColors.sunset;
  static const teal = PitakaColors.teal;

  static final sunset = _build(
    name: 'Sunset',
    seed: PitakaColors.sunset,
    accent: PitakaColors.sunset,
    deep: PitakaColors.sunsetDeep,
    container: PitakaColors.sunsetContainer,
    onDark: PitakaColors.sunsetOnDark,
  );

  static final tealPalette = _build(
    name: 'Teal',
    seed: PitakaColors.teal,
    accent: PitakaColors.teal,
    deep: PitakaColors.tealDeep,
    container: PitakaColors.tealContainer,
    onDark: PitakaColors.tealOnDark,
  );

  /// Any other saved or custom color keeps the Pitaka structure; only the
  /// accent family follows the color.
  static AppPalette fromSeed(String name, Color seed) {
    final hsl = HSLColor.fromColor(seed);
    Color at(double s, double l) => HSLColor.fromAHSL(1, hsl.hue, s, l).toColor();
    return _build(
      name: name,
      seed: seed,
      accent: seed,
      deep: at(math.min(hsl.saturation, 0.85), math.min(hsl.lightness, 0.40)),
      container: at(math.min(hsl.saturation, 0.90), 0.92),
      onDark: at(math.min(hsl.saturation, 0.90), math.max(hsl.lightness, 0.70)),
    );
  }

  static AppPalette _build({
    required String name,
    required Color seed,
    required Color accent,
    required Color deep,
    required Color container,
    required Color onDark,
  }) {
    return AppPalette(
      id: seed.toARGB32(),
      name: name,
      seed: seed,
      light: _light(accent: accent, deep: deep, container: container),
      dark: _dark(accent: accent, deep: deep, container: container, onDark: onDark),
    );
  }

  static ThemeTokens _light({required Color accent, required Color deep, required Color container}) {
    const bg = PitakaColors.lightBackground;
    const card = PitakaColors.lightSurface;
    const high = PitakaColors.lightSurfaceHigh;
    final surfaces = [bg, card, high];
    final onContainer = Contrast.ensure(deep, container);
    return ThemeTokens(
      brightness: Brightness.light,
      main: bg,
      onMain: _ensureAll(PitakaColors.lightInk, surfaces),
      onMainMuted: _ensureAll(PitakaColors.lightInkMuted, surfaces),
      second: card,
      secondHigh: high,
      onSecond: _ensureAll(PitakaColors.lightInk, [card, high]),
      onSecondMuted: _ensureAll(PitakaColors.lightInkMuted, [card, high, PitakaColors.lightInfo]),
      outline: PitakaColors.lightBorder,
      accent: accent,
      onAccent: Colors.white,
      accentOnSecond: _ensureAll(deep, [card, bg, high]),
      accentContainer: container,
      onAccentContainer: onContainer,
      heroStart: accent,
      heroEnd: deep,
      onHero: Colors.white,
      onHeroMuted: Colors.white.withValues(alpha: 0.86),
      success: _ensureAll(PitakaColors.lightSuccess, [card, bg]),
      successContainer: PitakaColors.lightSuccessContainer,
      onSuccessContainer: Contrast.ensure(PitakaColors.lightSuccess, PitakaColors.lightSuccessContainer),
      warning: _ensureAll(PitakaColors.lightWarning, [card, bg]),
      warningContainer: PitakaColors.lightWarningContainer,
      onWarningContainer: Contrast.ensure(PitakaColors.lightOnWarning, PitakaColors.lightWarningContainer),
      danger: _ensureAll(PitakaColors.lightDanger, [card, bg]),
      dangerContainer: PitakaColors.lightDangerContainer,
      onDangerContainer: Contrast.ensure(PitakaColors.lightDanger, PitakaColors.lightDangerContainer),
      neutralContainer: PitakaColors.lightNeutral,
      onNeutralContainer: Contrast.ensure(PitakaColors.lightOnNeutral, PitakaColors.lightNeutral),
      infoContainer: PitakaColors.lightInfo,
      inverseSurface: PitakaColors.lightInverse,
      onInverseSurface: const Color(0xFFF8FAFC),
      inverseAccent: Contrast.ensure(_lift(accent), PitakaColors.lightInverse),
      scrim: Colors.black.withValues(alpha: 0.45),
    );
  }

  static ThemeTokens _dark({required Color accent, required Color deep, required Color container, required Color onDark}) {
    const bg = PitakaColors.darkBackground;
    const card = PitakaColors.darkSurface;
    const high = PitakaColors.darkSurfaceHigh;
    final surfaces = [bg, card, high];
    return ThemeTokens(
      brightness: Brightness.dark,
      main: bg,
      onMain: _ensureAll(PitakaColors.darkInk, surfaces),
      onMainMuted: _ensureAll(PitakaColors.darkInkMuted, surfaces),
      second: card,
      secondHigh: high,
      onSecond: _ensureAll(PitakaColors.darkInk, [card, high]),
      onSecondMuted: _ensureAll(PitakaColors.darkInkMuted, [card, high, PitakaColors.darkInfo]),
      outline: PitakaColors.darkBorder,
      accent: accent,
      onAccent: Colors.white,
      accentOnSecond: _ensureAll(onDark, [card, bg, high]),
      // The tonal peach / mint stays light in dark mode (Figma dark frames).
      accentContainer: container,
      onAccentContainer: Contrast.ensure(deep, container),
      heroStart: accent,
      heroEnd: deep,
      onHero: Colors.white,
      onHeroMuted: Colors.white.withValues(alpha: 0.86),
      success: _ensureAll(PitakaColors.darkSuccess, [card, bg]),
      successContainer: PitakaColors.darkSuccessContainer,
      onSuccessContainer: Contrast.ensure(PitakaColors.darkSuccess, PitakaColors.darkSuccessContainer),
      warning: _ensureAll(PitakaColors.darkWarning, [card, bg]),
      warningContainer: PitakaColors.darkWarningContainer,
      onWarningContainer: Contrast.ensure(PitakaColors.darkOnWarning, PitakaColors.darkWarningContainer),
      danger: _ensureAll(PitakaColors.darkDanger, [card, bg]),
      dangerContainer: PitakaColors.darkDangerContainer,
      onDangerContainer: Contrast.ensure(PitakaColors.darkDanger, PitakaColors.darkDangerContainer),
      neutralContainer: PitakaColors.darkNeutral,
      onNeutralContainer: Contrast.ensure(PitakaColors.darkOnNeutral, PitakaColors.darkNeutral),
      infoContainer: PitakaColors.darkInfo,
      inverseSurface: PitakaColors.darkInverse,
      onInverseSurface: const Color(0xFFF8FAFC),
      inverseAccent: Contrast.ensure(onDark, PitakaColors.darkInverse),
      scrim: Colors.black.withValues(alpha: 0.6),
    );
  }

  /// A lighter tint of [c] for use on the dark snackbar.
  static Color _lift(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness(math.max(hsl.lightness, 0.66)).toColor();
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

  /// The accents offered in Settings (Figma: Accent · Sunset, Accent · Teal).
  static final all = <AppPalette>[sunset, tealPalette];

  /// The palette saved in settings. Any other saved color (older versions
  /// offered more) or a custom color gets its own palette with the same
  /// structure; nothing saved = Sunset.
  static AppPalette byId(int? id) {
    if (id == null) return sunset;
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
  /// Falls back to the default (Sunset) palette for the current brightness
  /// when the theme wasn't built by AppTheme (e.g. a plain MaterialApp in a
  /// widget test), instead of crashing.
  ThemeTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<AppColors>()?.tokens ?? AppPalettes.sunset.tokens(theme.brightness);
  }
}
