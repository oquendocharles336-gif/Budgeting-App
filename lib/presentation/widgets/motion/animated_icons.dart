import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cascade.dart';

/// Micro-interactions for icons whose meaning is a state.
///
/// Each icon is drawn from one progress value t (0 = first state, 1 =
/// second). Changing state runs the controller forward or in reverse, so
/// the way out is exactly the way in played backwards. 200-400 ms, and an
/// instant jump when the OS asks for reduced motion.
class _ProgressIcon extends StatefulWidget {
  const _ProgressIcon({
    required this.active,
    required this.painter,
    required this.duration,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  final bool active;
  final CustomPainter Function(double t, Color color) painter;
  final Duration duration;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  State<_ProgressIcon> createState() => _ProgressIconState();
}

class _ProgressIconState extends State<_ProgressIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration, value: widget.active ? 1 : 0);

  @override
  void didUpdateWidget(_ProgressIcon old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active) return;
    if (Cascade.reduced(context)) {
      _controller.value = widget.active ? 1 : 0;
    } else if (widget.active) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(painter: widget.painter(_controller.value, color)),
        ),
      ),
    );
  }
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

// -----------------------------------------------------------------------------
// Search <-> close
// -----------------------------------------------------------------------------

/// Search (magnifier) that turns into an X when [open]. The lens circle
/// draws itself in toward the handle while the handle swings round into
/// one stroke of the X; the other stroke grows out of the middle.
class AnimatedSearchIcon extends StatelessWidget {
  const AnimatedSearchIcon({super.key, required this.open, this.size = 24, this.color});
  final bool open;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => _ProgressIcon(
        active: open,
        duration: const Duration(milliseconds: 320),
        size: size,
        color: color,
        semanticLabel: open ? 'Close search' : 'Search',
        painter: (t, c) => _SearchPainter(t, c),
      );
}

class _SearchPainter extends CustomPainter {
  _SearchPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    final paint = _stroke(color, 2.2);
    final e = Curves.easeInOutCubic.transform(t);

    // Lens: shrinks its sweep to nothing at the handle's joint (45°).
    final sweep = 2 * math.pi * (1 - Curves.easeIn.transform((t * 1.4).clamp(0.0, 1.0)));
    if (sweep > 0.01) {
      final center = Offset.lerp(const Offset(10, 10), const Offset(12, 12), e)!;
      canvas.drawArc(Rect.fromCircle(center: center, radius: 6.2), math.pi / 4, sweep, false, paint);
    }

    // Handle: swings from 45° (down-right) round to 135°, growing into the
    // "/" stroke of the X.
    final angle = _lerp(math.pi / 4, math.pi * 3 / 4, e);
    final mid = Offset.lerp(const Offset(17.2, 17.2), const Offset(12, 12), e)!;
    final half = _lerp(3.6, 8.5, e);
    final d = Offset(math.cos(angle), math.sin(angle)) * half;
    canvas.drawLine(mid - d, mid + d, paint);

    // The "\" stroke grows from the centre in the second half.
    final g = Curves.easeOutCubic.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0));
    if (g > 0) {
      final d2 = const Offset(1, 1) / math.sqrt2 * 8.5 * g;
      canvas.drawLine(const Offset(12, 12) - d2, const Offset(12, 12) + d2, paint);
    }
  }

  @override
  bool shouldRepaint(_SearchPainter old) => old.t != t || old.color != color;
}

// -----------------------------------------------------------------------------
// Lock <-> unlock
// -----------------------------------------------------------------------------

/// Padlock. When [unlocked] the shackle springs up, overshoots a little,
/// then swings open around its right leg. Locking plays it backwards.
class AnimatedLockIcon extends StatelessWidget {
  const AnimatedLockIcon({super.key, required this.unlocked, this.size = 24, this.color});
  final bool unlocked;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => _ProgressIcon(
        active: unlocked,
        duration: const Duration(milliseconds: 380),
        size: size,
        color: color,
        semanticLabel: unlocked ? 'Unlocked' : 'Locked',
        painter: (t, c) => _LockPainter(t, c),
      );
}

class _LockPainter extends CustomPainter {
  _LockPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final fill = Paint()..color = color;
    final stroke = _stroke(color, 2.2);

    // Body.
    canvas.drawRRect(RRect.fromLTRBR(5, 11, 19, 21, const Radius.circular(2.5)), fill);

    // Phase 1 (0-60%): spring up 3px with a small overshoot.
    final lift = -3.2 * Curves.easeOutBack.transform((t / 0.6).clamp(0.0, 1.0));
    // Phase 2 (45-100%): swing open around the right leg.
    final swing = -0.65 * Curves.easeOutCubic.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));

    canvas.save();
    canvas.translate(0, lift);
    const pivot = Offset(16, 11);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(swing);
    canvas.translate(-pivot.dx, -pivot.dy);
    final shackle = Path()
      ..moveTo(8, 11.5)
      ..lineTo(8, 8)
      ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(4))
      ..lineTo(16, 11.5);
    canvas.drawPath(shackle, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LockPainter old) => old.t != t || old.color != color;
}

// -----------------------------------------------------------------------------
// Check
// -----------------------------------------------------------------------------

/// A check mark that draws itself in when [checked], and erases backwards.
class AnimatedCheckIcon extends StatelessWidget {
  const AnimatedCheckIcon({super.key, this.checked = true, this.size = 24, this.color, this.playOnMount = false});
  final bool checked;
  final double size;
  final Color? color;

  /// Draw in once when first shown (e.g. a "Saved" message).
  final bool playOnMount;

  @override
  Widget build(BuildContext context) => playOnMount
      ? _PlayOnMount(
          builder: (active) => _ProgressIcon(
            active: active,
            duration: const Duration(milliseconds: 300),
            size: size,
            color: color,
            semanticLabel: 'Done',
            painter: (t, c) => _CheckPainter(t, c),
          ),
        )
      : _ProgressIcon(
          active: checked,
          duration: const Duration(milliseconds: 300),
          size: size,
          color: color,
          semanticLabel: checked ? 'Done' : null,
          painter: (t, c) => _CheckPainter(t, c),
        );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    canvas.scale(size.width / 24);
    final path = Path()
      ..moveTo(5, 12.5)
      ..lineTo(10, 17.5)
      ..lineTo(19.5, 7);
    final e = Curves.easeOutCubic.transform(t);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * e), _stroke(color, 2.6));
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// Flips from false to true right after the first frame.
class _PlayOnMount extends StatefulWidget {
  const _PlayOnMount({required this.builder});
  final Widget Function(bool active) builder;

  @override
  State<_PlayOnMount> createState() => _PlayOnMountState();
}

class _PlayOnMountState extends State<_PlayOnMount> {
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _active = true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_active);
}

// -----------------------------------------------------------------------------
// Plus <-> close, menu <-> close
// -----------------------------------------------------------------------------

/// "+" that turns a quarter-and-a-bit into "×" when [open] (e.g. while the
/// add screen it opened is showing), and back when closed.
class AnimatedPlusIcon extends StatelessWidget {
  const AnimatedPlusIcon({super.key, required this.open, this.size = 30, this.color});
  final bool open;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        turns: open ? 0.125 : 0,
        duration: Cascade.reduced(context) ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        child: Icon(Icons.add_rounded, size: size, color: color),
      );
}

/// Hamburger menu <-> close, using Flutter's built-in morph.
class AnimatedMenuIcon extends StatefulWidget {
  const AnimatedMenuIcon({super.key, required this.open, this.color});
  final bool open;
  final Color? color;

  @override
  State<AnimatedMenuIcon> createState() => _AnimatedMenuIconState();
}

class _AnimatedMenuIconState extends State<AnimatedMenuIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: widget.open ? 1 : 0);

  @override
  void didUpdateWidget(AnimatedMenuIcon old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    if (Cascade.reduced(context)) {
      _controller.value = widget.open ? 1 : 0;
    } else {
      if (widget.open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
        icon: AnimatedIcons.menu_close,
        progress: _controller,
        color: widget.color,
        semanticLabel: widget.open ? 'Close' : 'Menu',
      );
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
