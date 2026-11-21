import 'package:flutter/material.dart';

import 'cascade.dart';

/// An [IndexedStack] that fades and slightly slides the new tab in when
/// [index] changes (about 300 ms, ease-out). Every child stays mounted, so
/// tab state, scroll positions and loaded data are kept: switching never
/// rebuilds or flickers a screen. Hidden tabs have their tickers paused.
///
/// The slide follows the direction of travel (a tab to the right comes in
/// from the right). With "Remove animations" on, tabs switch instantly.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 300),
    this.slide = 0.03,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  /// How far the new tab starts, as a fraction of its width.
  final double slide;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration, value: 1);
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late Animation<Offset> _offset = _offsetFor(1);

  Animation<Offset> _offsetFor(int direction) =>
      Tween<Offset>(begin: Offset(widget.slide * direction, 0), end: Offset.zero).animate(_curve);

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _controller.duration = widget.duration;
    if (old.index == widget.index) return;
    if (Cascade.reduced(context)) {
      _controller.value = 1;
      return;
    }
    _offset = _offsetFor(widget.index > old.index ? 1 : -1);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: _offset,
          child: IndexedStack(
            index: widget.index,
            children: [
              for (var i = 0; i < widget.children.length; i++)
                TickerMode(enabled: i == widget.index, child: widget.children[i]),
            ],
          ),
        ),
      );
}
