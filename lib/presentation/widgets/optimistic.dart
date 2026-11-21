import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/business_service.dart';
import '../providers/core_providers.dart';
import 'saved_snack.dart';

/// The optimistic pattern used by every form: show the change and "Saved"
/// at once, write in the background, and if the write fails take the change
/// back out and offer "Try again", which repeats the SAME write (same
/// operation key inside [write], so it can never be saved twice and the
/// user never retypes anything).
///
/// Everything needed later is captured from [context] up front, because
/// the form usually closes right after calling this.
class OptimisticWrite {
  OptimisticWrite._();

  static void run(
    BuildContext context, {
    required String savedText,
    required String what,
    required VoidCallback Function(ProviderContainer container) show,
    required Future<void> Function() write,
    SnackBarAction? Function()? undo,
  }) {
    final theme = Theme.of(context);
    _attempt(
      container: ProviderScope.containerOf(context, listen: false),
      messenger: ScaffoldMessenger.of(context),
      textColor: snackTextColor(context),
      errorColor: theme.colorScheme.error,
      onError: theme.colorScheme.onError,
      savedText: savedText,
      what: what,
      show: show,
      write: write,
      undo: undo,
    );
  }

  static void _attempt({
    required ProviderContainer container,
    required ScaffoldMessengerState messenger,
    required Color? textColor,
    required Color errorColor,
    required Color onError,
    required String savedText,
    required String what,
    required VoidCallback Function(ProviderContainer container) show,
    required Future<void> Function() write,
    SnackBarAction? Function()? undo,
  }) {
    VoidCallback remove;
    try {
      remove = show(container);
    } catch (e) {
      debugPrint('Session closed: $e'); // locked meanwhile
      return;
    }
    showSavedSnack(messenger, text: savedText, textColor: textColor);

    write().then((_) {
      try {
        // Reload first, then drop the preview: no flicker.
        container.read(dataRevisionProvider.notifier).bump();
        remove();
        final action = undo?.call();
        if (action != null) showSavedSnack(messenger, text: savedText, textColor: textColor, action: action);
      } catch (e) {
        debugPrint('Session closed before the save finished: $e');
      }
    }, onError: (Object e) {
      debugPrint('Save failed: $e');
      try {
        remove();
      } catch (_) {
        // Nothing left to roll back.
      }
      // Rules the user has to fix (not enough capital, missing name) can't
      // succeed on a retry, so those get their message only.
      final fixable = e is ArgumentError || e is StateError || e is CapitalLimitException || e is ShortStockException;
      final reason = e is ArgumentError ? '${e.message}' : '$e';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: errorColor,
          duration: const Duration(seconds: 10),
          content: Text(
            fixable ? 'Couldn\'t save $what: $reason. Nothing changed.' : 'Couldn\'t save $what, so it was taken back out. Nothing changed.',
            style: TextStyle(color: onError),
          ),
          action: fixable
              ? null
              : SnackBarAction(
                  label: 'Try again',
                  textColor: onError,
                  onPressed: () => _attempt(
                    container: container,
                    messenger: messenger,
                    textColor: textColor,
                    errorColor: errorColor,
                    onError: onError,
                    savedText: savedText,
                    what: what,
                    show: show,
                    write: write,
                    undo: undo,
                  ),
                ),
        ));
    });
  }
}
