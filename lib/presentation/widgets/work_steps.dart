import 'package:material_ui/material_ui.dart';

import 'motion/animated_icons.dart';

/// One step of a longer job, e.g. "Read 120 rows".
class WorkStep {
  const WorkStep(this.label, {this.done = false});
  final String label;
  final bool done;

  WorkStep finish([String? label]) => WorkStep(label ?? this.label, done: true);
}

/// Shows the work instead of a spinner: each step with its count, a check
/// mark as it finishes, and the current step highlighted.
class WorkSteps extends StatelessWidget {
  const WorkSteps({super.key, required this.steps});
  final List<WorkStep> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: s.done
                        ? AnimatedCheckIcon(playOnMount: true, size: 20, color: scheme.primary)
                        : Icon(Icons.more_horiz_rounded, size: 20, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.label,
                      style: TextStyle(
                        color: s.done ? scheme.onSurface : scheme.onSurfaceVariant,
                        fontWeight: s.done ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
