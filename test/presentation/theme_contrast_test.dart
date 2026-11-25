import 'package:budgeting_app/presentation/theme/app_palette.dart';
import 'package:budgeting_app/presentation/theme/app_theme.dart';
import 'package:budgeting_app/presentation/theme/glass.dart';
import 'package:budgeting_app/presentation/widgets/status_badge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('Midnight dark is midnight black / electric blue / sunset orange', () {
    final t = AppPalettes.midnight.dark;
    expect(t.main, AppPalettes.midnightBlack);
    expect(t.second, AppPalettes.electricNavy);
    expect(t.secondHigh, AppPalettes.electricNavyHigh);
    expect(t.glow, AppPalettes.electricBlue);
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

        // Colors used by Loans and the business screens.
        aa('muted labels on cards (tiles, hero cards)', t.onSecondMuted, t.second);
        aa('photo placeholder icon on secondHigh', t.onSecondMuted, t.secondHigh, Contrast.aaLarge);
        // Glass: text on the gradient background and on translucent cards,
        // at the brightest (or darkest) point of the background glow.
        final tinted = Color.alphaBlend(t.glow.withValues(alpha: Glass.tintAlpha), t.main);
        final glowBg = Color.alphaBlend(t.glow.withValues(alpha: Glass.glowAlpha(t)), tinted);
        final accentBg = Color.alphaBlend(t.accent.withValues(alpha: Glass.accentGlowAlpha), glowBg);
        for (final (name, bg) in [('plain', t.main), ('glow', glowBg), ('glow + accent', accentBg)]) {
          final card = Color.alphaBlend(Glass.fill(t), bg);
          aa('text on $name background', t.onMain, bg);
          aa('muted text on $name background', t.onMainMuted, bg);
          aa('body text on glass over $name', t.onMain, card);
          aa('muted body text on glass over $name', t.onMainMuted, card);
          aa('text on glass over $name', t.onSecond, card);
          aa('muted text on glass over $name', t.onSecondMuted, card);
          aa('key numbers on glass over $name', t.accentOnSecond, card);
          aa('success on glass over $name', t.success, card);
          aa('warning on glass over $name', t.warning, card);
          aa('danger on glass over $name', t.danger, card);
        }

        for (final tone in BadgeTone.values) {
          final c = BadgeColors.of(t, tone);
          aa('${tone.name} badge text', c.foreground, c.background);
          aa('${tone.name} badge icon', c.icon, c.background, Contrast.aaLarge);
        }
      });
    }
  }

  test('ThemeData maps tokens: background 60, glass cards 30, accent 10', () {
    final theme = AppTheme.dark(AppPalettes.sunsetOrange);
    final t = AppPalettes.midnight.dark;
    // The background is painted by each page route (GlassBackground).
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(Glass.backgroundGradient(t).colors.last, t.main);
    expect(theme.cardTheme.color, Glass.fill(t));
    expect(theme.colorScheme.primary, t.accent);
    expect(theme.dialogTheme.barrierColor, t.scrim);
  });
}