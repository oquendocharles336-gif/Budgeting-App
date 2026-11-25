import 'package:budgeting_app/presentation/theme/app_palette.dart';
import 'package:budgeting_app/presentation/theme/app_theme.dart';
import 'package:budgeting_app/presentation/widgets/status_badge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('Pitaka tokens match the Figma file', () {
    test('Theme · Light + Accent · Sunset', () {
      final t = AppPalettes.sunset.light;
      expect(t.main, PitakaColors.lightBackground);
      expect(t.second, PitakaColors.lightSurface);
      expect(t.secondHigh, PitakaColors.lightSurfaceHigh);
      expect(t.outline, PitakaColors.lightBorder);
      expect(t.accent, PitakaColors.sunset);
      expect(t.accentContainer, PitakaColors.sunsetContainer);
      expect(t.heroStart, PitakaColors.sunset);
      expect(t.heroEnd, PitakaColors.sunsetDeep);
      expect(t.infoContainer, PitakaColors.lightInfo);
      expect(t.inverseSurface, PitakaColors.lightInverse);
    });

    test('Theme · Dark + Accent · Sunset', () {
      final t = AppPalettes.sunset.dark;
      expect(t.main, PitakaColors.darkBackground);
      expect(t.second, PitakaColors.darkSurface);
      expect(t.secondHigh, PitakaColors.darkSurfaceHigh);
      expect(t.accent, PitakaColors.sunset);
      // The tonal peach stays light in dark mode, as in the dark frames.
      expect(t.accentContainer, PitakaColors.sunsetContainer);
    });

    test('Accent · Teal', () {
      final t = AppPalettes.tealPalette.light;
      expect(t.accent, PitakaColors.teal);
      expect(t.heroEnd, PitakaColors.tealDeep);
      expect(t.accentContainer, PitakaColors.tealContainer);
      // Only the accent family changes between accents.
      expect(t.main, AppPalettes.sunset.light.main);
      expect(t.second, AppPalettes.sunset.light.second);
    });

    test('saved settings: the old default id opens Sunset, other colors keep the structure', () {
      expect(AppPalettes.byId(null), same(AppPalettes.sunset));
      expect(AppPalettes.byId(AppPalettes.sunsetOrange.toARGB32()), same(AppPalettes.sunset));
      expect(AppPalettes.byId(AppPalettes.teal.toARGB32()), same(AppPalettes.tealPalette));
      final legacy = AppPalettes.byId(0xFF4F46E5); // "Indigo" from older versions
      expect(legacy.light.main, PitakaColors.lightBackground);
      expect(legacy.dark.second, PitakaColors.darkSurface);
      expect(legacy.light.accent, const Color(0xFF4F46E5));
    });
  });

  // Every offered accent, plus a custom / legacy color.
  final palettes = [...AppPalettes.all, AppPalettes.byId(0xFF4F46E5), AppPalettes.byId(0xFFCA8A04)];
  for (final palette in palettes) {
    for (final brightness in Brightness.values) {
      final t = palette.tokens(brightness);
      group('${palette.name} ${palette.seed.toARGB32().toRadixString(16)} ${brightness.name}', () {
        void aa(String what, Color fg, Color bg, [double min = Contrast.aa]) {
          test('$what ≥ $min:1', () {
            final r = Contrast.ratio(fg, bg);
            expect(r, greaterThanOrEqualTo(min), reason: '$what is ${r.toStringAsFixed(2)}:1');
          });
        }

        aa('text on background', t.onMain, t.main);
        aa('muted text on background', t.onMainMuted, t.main);
        aa('text on cards', t.onMain, t.second);
        aa('muted text on cards', t.onMainMuted, t.second);
        aa('onSecond on cards', t.onSecond, t.second);
        aa('onSecond on secondHigh', t.onSecond, t.secondHigh);
        aa('muted labels on cards', t.onSecondMuted, t.second);
        aa('muted labels in the preview panel', t.onSecondMuted, t.infoContainer);
        aa('icons on secondHigh', t.onSecondMuted, t.secondHigh, Contrast.aaLarge);
        aa('accent text on cards ("Mark unpaid")', t.accentOnSecond, t.second);
        aa('accent text on background ("Add")', t.accentOnSecond, t.main);
        aa('tonal button label ("Paid")', t.onAccentContainer, t.accentContainer);
        aa('success on cards', t.success, t.second);
        aa('warning on cards', t.warning, t.second);
        aa('danger on cards', t.danger, t.second);
        aa('"Loans returned" text', t.onSuccessContainer, t.successContainer);
        aa('"Heads up" banner text', t.onWarningContainer, t.warningContainer);
        aa('danger banner text', t.onDangerContainer, t.dangerContainer);
        aa('"Not in budget" chip text', t.onNeutralContainer, t.neutralContainer);
        aa('toast text', t.onInverseSurface, t.inverseSurface);
        aa('toast action ("Undo")', t.inverseAccent, t.inverseSurface);

        for (final tone in BadgeTone.values) {
          final c = BadgeColors.of(t, tone);
          aa('${tone.name} badge text', c.foreground, c.background);
          aa('${tone.name} badge icon', c.icon, c.background, Contrast.aaLarge);
        }
      });
    }
  }

  // The Figma brand fill (filled buttons, FAB, hero gradient start) is used
  // exactly as designed. White labels on it are bold and ≥16px but measure
  // below AA (Sunset 2.84:1, Teal 3.74:1). Recorded here so any change to
  // the brand fill or its label color is a deliberate one.
  for (final palette in AppPalettes.all) {
    test('${palette.name}: brand fill label contrast is at least the Figma value', () {
      final t = palette.light;
      expect(t.onAccent, Colors.white);
      expect(Contrast.ratio(t.onAccent, t.accent), greaterThanOrEqualTo(2.8));
    });
  }

  test('ThemeData maps the tokens: flat cards, accent, tonal containers, font', () {
    final theme = AppTheme.light(AppPalettes.sunsetOrange);
    final t = AppPalettes.sunset.light;
    expect(theme.scaffoldBackgroundColor, t.main);
    expect(theme.cardTheme.color, t.second);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.colorScheme.primary, t.accent);
    expect(theme.colorScheme.primaryContainer, t.accentContainer);
    expect(theme.colorScheme.onPrimaryContainer, t.onAccentContainer);
    expect(theme.dialogTheme.barrierColor, t.scrim);
    expect(theme.snackBarTheme.backgroundColor, t.inverseSurface);
    expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);

    final dark = AppTheme.dark(AppPalettes.sunsetOrange);
    expect(dark.scaffoldBackgroundColor, AppPalettes.sunset.dark.main);
    expect(dark.cardTheme.color, AppPalettes.sunset.dark.second);
  });
}
