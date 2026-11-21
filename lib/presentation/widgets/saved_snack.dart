import 'package:flutter/material.dart';

import 'motion/animated_icons.dart';

/// The optimistic "Saved ✓" message used across the app, with an optional
/// action (e.g. "Undo"). Capture [messenger] and [textColor] before closing
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
          AnimatedCheckIcon(playOnMount: true, size: 20, color: textColor),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ));
}

/// Snack text color from the theme (for [showSavedSnack]).
Color? snackTextColor(BuildContext context) => Theme.of(context).snackBarTheme.contentTextStyle?.color;
