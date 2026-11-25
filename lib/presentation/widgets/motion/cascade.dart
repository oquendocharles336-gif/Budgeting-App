import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Shared timing for list entrances.
class Cascade {
  Cascade._();

  /// Delay between rows: row index x 70 ms.
  static const step = Duration(milliseconds: 70);

  /// Length of one row's fade + slide.
  static const duration = Duration(milliseconds: 320);

  /// Only the first rows cascade; the rest appear at once so long lists
  /// never feel slow (12 x 70 ms = under a second).
  static const maxAnimated = 12;

  static const curve = Curves.easeOutCubic;

  /// After this, rows built later (scrolling, refreshes) just appear.
  static Duration get window => step * maxAnimated + duration;

  /// True when the user asked the OS for less motion.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Wrap a screen's list in this. Its rows ([CascadeIn]) animate in one
/// after another the first time they appear, and never again for the life
/// of the screen: not on rebuilds, refreshes or scrolling back.
class CascadeScope extends StatefulWidget {
  const CascadeScope({super.key, required this.child});
  final Widget child;

  @override
  State<CascadeScope> createState() => _CascadeScopeState();
}

class _CascadeScopeState extends State<CascadeScope> {
  /// Set when the first row shows up (data may arrive after a skeleton).
  DateTime? _start;

  Duration _elapsed() {
    final now = DateTime.now();
    final start = _start ??= now;
    return now.difference(start);
  }

  @override
  Widget build(BuildContext context) => _CascadeInherited(state: this, child: widget.child);
}

class _CascadeInherited extends InheritedWidget {
  const _CascadeInherited({required this.state, required super.child});
  final _CascadeScopeState state;

  @override
  bool updateShouldNotify(_CascadeInherited old) => false;
}

/// One row of a cascading list: fades in while sliding up a little, with
/// an ease-out curve (no bounce), delayed by `index x 70 ms`.
class CascadeIn extends StatefulWidget {
  const CascadeIn({super.key, required this.index, required this.child});

  /// Position in the list (0 = first). Rows past [Cascade.maxAnimated]
  /// appear immediately.
  final int index;
  final Widget child;

  @override
  State<CascadeIn> createState() => _CascadeInState();
}

class _CascadeInState extends State<CascadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: Cascade.duration);
  late final Animation<double> _curved = CurvedAnimation(parent: _controller, curve: Cascade.curve);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(_curved);
  Timer? _timer;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final scope = context.getInheritedWidgetOfExactType<_CascadeInherited>()?.state;
    if (scope == null || Cascade.reduced(context) || widget.index >= Cascade.maxAnimated) {
      _controller.value = 1;
      return;
    }
    final elapsed = scope._elapsed();
    if (elapsed >= Cascade.window) {
      _controller.value = 1; // The screen's entrance is over.
      return;
    }
    final wait = Cascade.step * widget.index - elapsed;
    if (wait <= Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(wait, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always the same wrappers, so a row's own state (e.g. a swipe) is kept.
    // At full opacity FadeTransition adds no layer, so finished rows stay cheap.
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
