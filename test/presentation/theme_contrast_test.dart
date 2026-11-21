import 'package:budgeting_app/presentation/theme/app_palette.dart';
import 'package:budgeting_app/presentation/theme/app_theme.dart';
import 'package:budgeting_app/presentation/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Midnight dark is midnight navy / graphite / sunset orange', () {
    final t = AppPalettes.midnight.dark;
    expect(t.main, AppPalettes.midnightBlack);
    expect(t.second, AppPalettes.graphite);
    expect(t.secondHigh, AppPalettes.graphiteHigh);
    expect(t.accent, AppPalettes.sunsetGlow);
  });

  for (final palette in AppPalettes.all) {
    for (final brightness in Brightness.values) {
      final t = palette.tokens(brightness);
      group('${palette.name} ${brightness.name}', () {
        void aa(String what, Color fg, Color bg, [double min = Contrast.aa]) {
          test('$what ≥ $min:1', () {
            final r = Contrast.ratio(fg, bg);
            expect(r, greaterThanOrEqualTo(min), reason: '$what is ${r.toStringAsFixed(2)}:1');
          });
        }

        aa('text on main', t.onMain, t.main);
        aa('muted text on main', t.onMainMuted, t.main);
        aa('text on cards', t.onMain, t.second);
        aa('muted text on cards', t.onMainMuted, t.second);
        aa('onSecond on second', t.onSecond, t.second);
        aa('onSecond on secondHigh', t.onSecond, t.secondHigh);
        aa('button label on accent', t.onAccent, t.accent);
        aa('key numbers on cards', t.accentOnSecond, t.second);
        aa('success on cards', t.success, t.second);
        aa('warning on cards', t.warning, t.second);
        aa('danger on cards', t.danger, t.second);
        aa('accent button vs background', t.accent, t.main, Contrast.aaLarge);

        // Colors used by Pay Later, Loans and the business screens.
        aa('muted labels on cards (tiles, hero cards)', t.onSecondMuted, t.second);
        aa('photo placeholder icon on secondHigh', t.onSecondMuted, t.secondHigh, Contrast.aaLarge);
        for (final tone in BadgeTone.values) {
          final c = BadgeColors.of(t, tone);
          aa('${tone.name} badge text', c.foreground, c.background);
          aa('${tone.name} badge icon', c.icon, c.background, Contrast.aaLarge);
        }
      });
    }
  }

  test('ThemeData maps tokens: background 60, cards 30, accent 10', () {
    final theme = AppTheme.dark(AppPalettes.sunsetOrange);
    final t = AppPalettes.midnight.dark;
    expect(theme.scaffoldBackgroundColor, t.main);
    expect(theme.cardTheme.color, t.second);
    expect(theme.colorScheme.primary, t.accent);
    expect(theme.dialogTheme.barrierColor, t.scrim);
  });
}