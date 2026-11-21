import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Glassmorphism, in one place: frosted translucent surfaces with a thin
/// light edge and a soft shadow, over a gradient background.
///
/// Built on the 60/30/10 tokens: the background is the 60% [ThemeTokens.main]
/// with a soft glow of the 30% hue ([ThemeTokens.glow]; electric blue in
/// Midnight dark), glass is the 30% [ThemeTokens.second] made translucent,
/// and the accent stays the only loud color. The alphas below are chosen so
/// every text token keeps WCAG AA on glass at the brightest point of the
/// background (see test/presentation/theme_contrast_test.dart).
class Glass {
  Glass._();

  static const blur = 16.0;
  static const radius = 20.0;

  /// Backdrop blur on cards ([AppCard]). Set to false if scrolling long
  /// lists stutters on older phones: cards keep the translucent glass look
  /// (the background behind them is a smooth gradient), only the blur goes.
  static const blurCards = true;

  /// Peak opacity of the background glow (radial, top left).
  static double glowAlpha(ThemeTokens t) => t.isDark ? 0.18 : 0.30;

  /// The linear tint under it (also the 30% hue).
  static const tintAlpha = 0.06;

  /// Peak opacity of the faint accent glow (bottom corner).
  static const accentGlowAlpha = 0.10;

  /// Card fill: the 30% color, translucent.
  static Color fill(ThemeTokens t, {bool strong = false}) =>
      t.second.withValues(alpha: t.isDark ? (strong ? 0.80 : 0.60) : (strong ? 0.84 : 0.62));

  /// Bars (bottom navigation, app bars when scrolled): a little more solid.
  static Color barFill(ThemeTokens t) => t.second.withValues(alpha: t.isDark ? 0.72 : 0.74);

  /// The thin light edge.
  static Color border(ThemeTokens t) => t.isDark
      ? Color.alphaBlend(t.glow.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.06))
      : Colors.white.withValues(alpha: 0.75);

  static BorderSide side(ThemeTokens t) => BorderSide(color: border(t), width: 1);

  /// Soft shadow; [lift] > 0 for a raised (floating) surface.
  static List<BoxShadow> shadow(ThemeTokens t, {double lift = 0}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: (t.isDark ? 0.32 : 0.08) + lift * (t.isDark ? 0.18 : 0.10)),
          blurRadius: 18 + lift * 14,
          spreadRadius: -2,
          offset: Offset(0, 6 + lift * 6),
        ),
      ];

  /// The 60% background with a light tint of the 30% hue.
  static LinearGradient backgroundGradient(ThemeTokens t) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(t.glow.withValues(alpha: tintAlpha), t.main),
          t.main,
          t.main,
        ],
        stops: const [0, 0.55, 1],
      );
}

/// The gradient background with two soft glows. Every page gets it (see
/// [GlassPageTransitionsBuilder]), so screens keep transparent Scaffolds.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: Glass.backgroundGradient(t)),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.9, -0.85),
                      radius: 1.1,
                      colors: [t.glow.withValues(alpha: Glass.glowAlpha(t)), t.glow.withValues(alpha: 0)],
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(1.1, 0.95),
                        radius: 0.9,
                        colors: [t.accent.withValues(alpha: Glass.accentGlowAlpha), t.accent.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A frosted glass surface: blur behind, translucent fill, thin light
/// border, soft shadow. Use it (or [AppCard], which uses it) for cards.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = Glass.radius,
    this.onTap,
    this.strong = false,
    this.lift = 0,
    this.blur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// A more solid fill (for surfaces over busy content).
  final bool strong;

  /// 0 = resting, 1 = floating (bigger shadow).
  final double lift;

  /// Turn off for long lists of small items, where the blur costs more
  /// than it shows (the background behind is a smooth gradient anyway).
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shape = BorderRadius.circular(radius);
    Widget content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
    content = DecoratedBox(
      decoration: BoxDecoration(
        color: Glass.fill(t, strong: strong),
        borderRadius: shape,
        border: Border.fromBorderSide(Glass.side(t)),
      ),
      child: content,
    );
    if (blur) {
      content = BackdropFilter(filter: ImageFilter.blur(sigmaX: Glass.blur, sigmaY: Glass.blur), child: content);
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: Glass.shadow(t, lift: lift)),
      child: ClipRRect(borderRadius: shape, child: content),
    );
  }
}

/// A frosted bar (bottom navigation): blur + translucent fill + top edge.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Glass.blur, sigmaY: Glass.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Glass.barFill(t),
            border: Border(top: Glass.side(t)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Gives every page route the glass background, keeping the platform's
/// normal page transition. Pages are opaque this way, so a page sliding in
/// never shows the one below through its transparent Scaffold.
class GlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlassPageTransitionsBuilder();

  static const _defaults = PageTransitionsTheme();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final platform = Theme.of(context).platform;
    final inner = _defaults.builders[platform] ?? const ZoomPageTransitionsBuilder();
    return inner.buildTransitions<T>(route, context, animation, secondaryAnimation, GlassBackground(child: child));
  }
}
