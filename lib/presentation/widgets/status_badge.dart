import 'package:material_ui/material_ui.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

enum BadgeTone { ok, warning, danger, neutral, accent }

/// Colors for a small status pill (Figma "StatusBadge"): a tinted container
/// with a darker label. Built only from theme tokens and nudged to WCAG AA:
/// text 4.5:1 and icon 3:1 on the pill (checked in
/// test/presentation/theme_contrast_test.dart for every palette).
class BadgeColors {
  BadgeColors._();

  static Color toneColor(ThemeTokens t, BadgeTone tone) => switch (tone) {
        BadgeTone.ok => t.success,
        BadgeTone.warning => t.warning,
        BadgeTone.danger => t.danger,
        BadgeTone.neutral => t.onNeutralContainer,
        BadgeTone.accent => t.onAccentContainer,
      };

  static ({Color background, Color foreground, Color icon}) of(ThemeTokens t, BadgeTone tone) {
    final (background, label) = switch (tone) {
      BadgeTone.ok => (t.successContainer, t.onSuccessContainer),
      BadgeTone.warning => (t.warningContainer, t.onWarningContainer),
      BadgeTone.danger => (t.dangerContainer, t.onDangerContainer),
      BadgeTone.neutral => (t.neutralContainer, t.onNeutralContainer),
      BadgeTone.accent => (t.accentContainer, t.onAccentContainer),
    };
    return (
      background: background,
      foreground: Contrast.ensure(label, background),
      icon: Contrast.ensure(label, background, target: Contrast.aaLarge),
    );
  }
}

/// "Unpaid", "Paid Nov 20 · Cash", "Not in budget"... The meaning is in the
/// text, not only the color, so it also works for color-blind users and
/// screen readers.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.tone = BadgeTone.neutral, this.icon});
  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = BadgeColors.of(context.tokens, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2, vertical: Space.xxs),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(Radii.chip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: Icon(icon, size: 15, color: c.icon)),
            const SizedBox(width: Space.xxs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.foreground, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
