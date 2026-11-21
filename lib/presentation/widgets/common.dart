import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction_entry.dart';
import '../../domain/budget/budget_calculator.dart';
import '../providers/app_state_providers.dart';
import '../theme/app_theme.dart';
import '../theme/category_icons.dart';

extension AsyncDataOrNull<T> on AsyncValue<T> {
  /// The current (or previous, while refreshing) value, or null.
  T? get asDataOrNull => hasValue ? requireValue : null;
}

/// Shows loading / error / data for an AsyncValue without flashing a
/// spinner when data refreshes in the background.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loading});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    if (value.hasError) return ErrorView(error: value.error!, onRetry: onRetry);
    if (value.hasValue) return data(value.requireValue);
    return loading ?? const LoadingView();
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('Something went wrong', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('$error', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      );
}

/// Rounded surface used for most content blocks.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// Formats centavos with the user's currency.
class AmountText extends ConsumerWidget {
  const AmountText(this.centavos, {super.key, this.style, this.kind, this.colored = false});

  final int centavos;
  final TextStyle? style;

  /// When set, expenses get a "-" and income a "+".
  final TransactionKind? kind;
  final bool colored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final symbol = ref.watch(currencyProvider).symbol;
    var text = Money.format(centavos, symbol: symbol);
    Color? color;
    if (kind == TransactionKind.expense) {
      text = '-$text';
    } else if (kind == TransactionKind.income) {
      text = '+$text';
      if (colored) color = StatusColors.income(context);
    }
    return Text(text, style: (style ?? const TextStyle()).copyWith(color: color));
  }
}

/// Use inside build() only (it watches the currency setting).
String formatMoney(WidgetRef ref, int centavos) => Money.format(centavos, symbol: ref.watch(currencyProvider).symbol);

Color budgetColor(BuildContext context, BudgetLevel level) => switch (level) {
      BudgetLevel.exceeded => StatusColors.danger(context),
      BudgetLevel.warning => StatusColors.warning(context),
      _ => StatusColors.ok(context),
    };

class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({super.key, required this.progress, this.height = 10, this.onDark = false});
  final BudgetProgress progress;
  final double height;

  /// Use white track colors (for gradient hero cards).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : budgetColor(context, progress.level);
    final track = onDark ? Colors.white24 : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: '${progress.percentUsed} percent of budget used',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress.ratio.clamp(0.0, 1.0).toDouble()),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor: track,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 44});
  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category?.color ?? 0xFF78909C);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(CategoryIcons.of(category?.icon ?? 'other'), color: color, size: size * 0.5),
    );
  }
}

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onPrevious, required this.onNext});
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Previous month'),
        SizedBox(
          width: 150,
          child: Text(
            DateFormat('MMMM yyyy').format(month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          onPressed: isCurrent ? null : onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                  minimumSize: const Size(88, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : null,
    ));
}

/// Reusable money input formatter/validator.
String? validateAmount(String? text, {bool allowZero = false}) {
  if (text == null || text.trim().isEmpty) return 'Enter an amount';
  final v = Money.parse(text);
  if (v == null) return 'Enter a valid amount, e.g. 150.50';
  if (v < 0) return 'Amount can\'t be negative';
  if (!allowZero && v == 0) return 'Amount must be more than zero';
  if (v > 99999999999) return 'Amount is too large';
  return null;
}
