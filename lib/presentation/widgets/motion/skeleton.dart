import 'package:material_ui/material_ui.dart';

import '../../theme/app_palette.dart';
import 'cascade.dart';

/// Gray placeholder shapes in the layout of the real content, with a soft
/// shimmer (static when the OS asks for reduced motion). Shown while data
/// loads instead of a spinner, so the wait feels shorter.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});
  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Cascade.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final base = t.secondHigh;
    final shine = Color.alphaBlend(t.onSecond.withValues(alpha: 0.08), base);
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              final x = _controller.value * 2 - 0.5;
              return LinearGradient(
                colors: [base, shine, base],
                stops: [(x - 0.3).clamp(0.0, 1.0), x.clamp(0.0, 1.0), (x + 0.3).clamp(0.0, 1.0)],
              ).createShader(rect);
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 10});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: context.tokens.secondHigh, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Placeholder for a list of rows (avatar, two lines, amount): the shape
/// of transactions, debts, budgets and categories.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 6, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16)});
  final int rows;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < rows; i++) const SkeletonRow()],
          ),
        ),
      );
}

class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SkeletonBox(width: 44, height: 44, radius: 14),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 150, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 90, height: 12),
                ],
              ),
            ),
            SizedBox(width: 14),
            SkeletonBox(width: 64, height: 16),
          ],
        ),
      );
}

/// Placeholder for a hero card / chart block of a given height.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Skeleton(child: SkeletonBox(height: height, radius: 24));
}
