import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import 'cascade.dart';

/// A stack of cards you swipe through like a wallet.
///
/// * The top card follows the finger and tilts with the drag.
/// * Released past ~35% of the width, or flicked fast enough, it flies off
///   in the direction of the release velocity and goes to the back.
///   Otherwise it springs back into place.
/// * The next card peeks out below (so it's clear there are more) and
///   moves up / scales in as the top card leaves.
class SwipeCardDeck<T> extends StatefulWidget {
  const SwipeCardDeck({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.keyOf,
    required this.onSwiped,
    this.onTap,
    this.aspectRatio = 1.6,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Object Function(T item) keyOf;
  final ValueChanged<T>? onTap;

  /// The top card ([items] first) was swiped away: the parent moves it to
  /// the back of [items]. The deck itself always shows `items.first` on top.
  final ValueChanged<T> onSwiped;
  final double aspectRatio;

  @override
  State<SwipeCardDeck<T>> createState() => _SwipeCardDeckState<T>();
}

class _SwipeCardDeckState<T> extends State<SwipeCardDeck<T>> with SingleTickerProviderStateMixin {
  static const _peek = 14.0;
  static const _flingVelocity = 700.0;
  static const _distanceFraction = 0.35;

  late final AnimationController _anim = AnimationController.unbounded(vsync: this)..addListener(_onTick);
  double _dx = 0;
  double _from = 0;
  double _to = 0;
  double _width = 1;

  int get _count => widget.items.length;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onTick() => setState(() => _dx = _from + (_to - _from) * _anim.value);

  void _onDragStart(DragStartDetails _) => _anim.stop();

  void _onDragUpdate(DragUpdateDetails d) => setState(() => _dx += d.delta.dx);

  void _onDragEnd(DragEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    final fast = vx.abs() > _flingVelocity;
    final far = _dx.abs() > _width * _distanceFraction;
    if (_count > 1 && (far || fast)) {
      _flingAway(fast ? vx.sign : _dx.sign, vx);
    } else {
      _springBack(vx);
    }
  }

  /// Carries on with the release velocity until the card is off-screen.
  void _flingAway(double direction, double vx) {
    final reduced = Cascade.reduced(context);
    _from = _dx;
    _to = direction * _width * 1.5;
    final distance = (_to - _from).abs();
    final speed = math.max(vx.abs(), 1400.0);
    final ms = reduced ? 0 : (distance / speed * 1000).clamp(140.0, 360.0).round();
    _anim.value = 0;
    _anim.animateTo(1, duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic).whenCompleteOrCancel(() {
      if (!mounted || _anim.value < 1) return;
      final gone = widget.items.first;
      setState(() {
        _from = 0;
        _to = 0;
        _dx = 0;
      });
      _anim.value = 0;
      // Same frame: the parent re-orders, so the next card is simply on top.
      widget.onSwiped(gone);
    });
  }

  /// Spring physics back to the centre, starting at the release velocity.
  void _springBack(double vx) {
    if (_dx == 0) return;
    _from = 0;
    _to = _dx;
    if (Cascade.reduced(context)) {
      _anim.value = 0;
      return;
    }
    // value 1 = where it was released, 0 = home; velocity in those units.
    final velocity = vx / _dx;
    final spring = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 420, damping: 36),
      1,
      0,
      velocity,
    );
    _anim.animateWith(spring);
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final reduced = Cascade.reduced(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final cardHeight = _width / widget.aspectRatio;
        // How far the top card has gone: drives the cards behind it.
        final progress = (_dx.abs() / (_width * 0.5)).clamp(0.0, 1.0);
        final layers = math.min(_count, 3);
        return SizedBox(
          height: cardHeight + _peek * (layers - 1),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var depth = layers - 1; depth >= 0; depth--)
                _layer(context, depth, progress, cardHeight, reduced),
            ],
          ),
        );
      },
    );
  }

  Widget _layer(BuildContext context, int depth, double progress, double cardHeight, bool reduced) {
    final item = widget.items[depth];
    final card = SizedBox(width: _width, height: cardHeight, child: widget.itemBuilder(context, item));
    if (depth == 0) {
      final angle = reduced ? 0.0 : (_dx / _width) * 0.3;
      return Positioned(
        key: ValueKey(widget.keyOf(item)),
        left: 0,
        right: 0,
        top: 0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onTap: widget.onTap == null ? null : () => widget.onTap!(item),
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Transform.rotate(angle: angle, alignment: Alignment.bottomCenter, child: card),
          ),
        ),
      );
    }
    // Cards behind: step down and shrink a little; move up as the top leaves.
    final level = depth - progress;
    final scale = 1 - 0.06 * level;
    return Positioned(
      key: ValueKey(widget.keyOf(item)),
      left: 0,
      right: 0,
      // Scaled from the top, so push it down enough that [_peek] px of its
      // bottom edge shows below the card in front (the "there's more" cue).
      top: cardHeight * (1 - scale) + _peek * level,
      child: IgnorePointer(
        child: Transform.scale(scale: scale, alignment: Alignment.topCenter, child: card),
      ),
    );
  }
}
