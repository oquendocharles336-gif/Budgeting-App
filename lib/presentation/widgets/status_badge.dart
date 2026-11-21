import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

enum BadgeTone { ok, warning, danger, neutral, accent }

/// Colors for a small status pill on a card. Built only from theme tokens,
/// and nudged to WCAG AA: text 4.5:1 and icon 3:1 on the pill (checked in
/// test/presentation/theme_contrast_test.dart for every palette).
class BadgeColors {
  BadgeColors._();

  static Color toneColor(ThemeTokens t, BadgeTone tone) => switch (tone) {
        BadgeTone.ok => t.success,
        BadgeTone.warning => t.warning,
        BadgeTone.danger => t.danger,
        BadgeTone.neutral => t.onSecondMuted,
        BadgeTone.accent => t.accentOnSecond,
      };

  static ({Color background, Color foreground, Color icon}) of(ThemeTokens t, BadgeTone tone) {
    final status = toneColor(t, tone);
    final background = Color.alphaBlend(status.withValues(alpha: 0.18), t.second);
    return (
      background: background,
      foreground: Contrast.ensure(t.onSecond, background),
      icon: Contrast.ensure(status, background, target: Contrast.aaLarge),
    );
  }
}

/// "Paid", "Due in 2 days", "Low stock"... The meaning is in the text, not
/// only the color, so it also works for color-blind users and screen readers.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.tone = BadgeTone.neutral, this.icon});
  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = BadgeColors.of(context.tokens, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c.icon),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.foreground, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
