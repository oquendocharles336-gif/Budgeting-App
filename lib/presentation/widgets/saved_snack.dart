import 'package:material_ui/material_ui.dart';

import '../theme/app_palette.dart';
import 'motion/animated_icons.dart';

/// The optimistic "Saved ✓" message used across the app (Figma "Toast"):
/// dark navy, a green check, the text, and an optional accent action
/// (e.g. "Undo", 6 s). Capture [messenger] and [textColor] before closing
/// a screen.
void showSavedSnack(
  ScaffoldMessengerState messenger, {
  required String text,
  Color? textColor,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: action == null ? duration : const Duration(seconds: 6),
      action: action,
      content: Row(
        children: [
          // The toast is dark in both themes, so the light green reads on it.
          const AnimatedCheckIcon(playOnMount: true, size: 20, color: PitakaColors.darkSuccess),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ));
}

/// Snack text color from the theme (for [showSavedSnack]).
Color? snackTextColor(BuildContext context) => Theme.of(context).snackBarTheme.contentTextStyle?.color;
