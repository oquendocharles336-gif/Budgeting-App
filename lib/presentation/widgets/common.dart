import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction_entry.dart';
import '../../domain/budget/budget_calculator.dart';
import '../providers/app_state_providers.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/category_icons.dart';
import 'motion/skeleton.dart';

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

/// Default loading state: skeleton rows in the shape of a list (never a
/// spinner). Clipped, so it fits any height it's given.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: SkeletonList(rows: rows),
        ),
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

  /// Figma "Loans · Empty": a 96px tonal circle with the icon in the
  /// accent, a bold title, a muted message and one filled pill action.
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxxl, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: t.accentContainer, shape: BoxShape.circle),
                child: Icon(icon, size: 44, color: t.onAccentContainer),
              ),
            ),
            const SizedBox(height: Space.xl),
            Text(title, textAlign: TextAlign.center, style: text.titleLarge?.copyWith(fontSize: 20)),
            if (message != null) ...[
              const SizedBox(height: Space.sm),
              Text(message!, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: t.onMainMuted)),
            ],
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ],
        ),
      ),
    );
  }
}

/// "Category budgets ............ Add": an 18px bold title on the
/// background with an optional accent text action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(2, Space.lg, 0, actionLabel == null ? Space.sm : 0),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18)),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.md)),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
          ],
        ),
      );
}

/// Figma "Card": a flat surface ([ThemeTokens.second]) with a 1px border
/// and 18px corners. Used for most content blocks.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = Radii.card,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Fill; defaults to the card color.
  final Color? color;

  /// Border; defaults to the outline token.
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: color ?? t.second,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? t.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Figma "HeroCard": the big number at the top of a screen, on the accent
/// gradient (Sunset #FF6B35 → #C2410C) with white text.
///
///     Unpaid loans
///     ₱2,500.00
///     2 unpaid · 2 paid
///     (◔ ₱1,000 deducted from November's budget)
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.chip,
    this.chipIcon,
    this.trailing,
    this.footer,
    this.onTap,
  });

  final String label;

  /// The big number (usually an [AmountText] or a Text). It gets the
  /// display style in white.
  final Widget value;
  final String? caption;

  /// A translucent pill under the caption.
  final String? chip;
  final IconData? chipIcon;

  /// Top-right corner (e.g. an icon button).
  final Widget? trailing;

  /// Extra content at the bottom (e.g. quick actions).
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final shape = BorderRadius.circular(Radii.hero);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: t.heroGradient, borderRadius: shape),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: t.onHero),
              child: IconTheme.merge(
                data: IconThemeData(color: t.onHero),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: text.bodyMedium?.copyWith(color: t.onHeroMuted, fontWeight: FontWeight.w600),
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                    const SizedBox(height: Space.xxs),
                    DefaultTextStyle.merge(
                      style: text.displaySmall?.copyWith(color: t.onHero),
                      child: value,
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: Space.xxs),
                      Text(caption!, style: text.bodyMedium?.copyWith(color: t.onHeroMuted)),
                    ],
                    if (chip != null) ...[
                      const SizedBox(height: Space.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(Radii.chip),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (chipIcon != null) ...[
                              ExcludeSemantics(child: Icon(chipIcon, size: 16, color: t.onHero)),
                              const SizedBox(width: Space.xs),
                            ],
                            Flexible(
                              child: Text(
                                chip!,
                                style: TextStyle(color: t.onHero, fontSize: 12.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (footer != null) ...[const SizedBox(height: Space.lg), footer!],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma "Tabs": pill segments, e.g. "Unpaid · 2 | Paid · 2". The selected
/// one gets the tonal accent fill.
class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.labels, required this.selected, required this.onChanged});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Container(
      decoration: BoxDecoration(
        color: t.second,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: t.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.chip),
        child: Row(
          children: [
            for (final (i, label) in labels.indexed)
              Expanded(
                child: Semantics(
                  selected: i == selected,
                  button: true,
                  inMutuallyExclusiveGroup: true,
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: reduced ? Duration.zero : Motion.fade,
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                      color: i == selected ? t.accentContainer : Colors.transparent,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: i == selected ? t.onAccentContainer : t.onSecondMuted,
                          fontWeight: i == selected ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Figma "Button / Tonal": a pill with the tonal accent fill, e.g. "✓ Paid".
class TonalPillButton extends StatelessWidget {
  const TonalPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.semanticsLabel,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Shows a small spinner instead of the icon and disables the button.
  final bool busy;
  final String? semanticsLabel;

  /// Full width (sheets: "Got it").
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = FilledButton.styleFrom(
      backgroundColor: t.accentContainer,
      foregroundColor: t.onAccentContainer,
      disabledBackgroundColor: t.accentContainer.withValues(alpha: 0.6),
      disabledForegroundColor: t.onAccentContainer.withValues(alpha: 0.7),
      minimumSize: expand ? const Size.fromHeight(52) : const Size(96, 48),
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
    );
    final labelText = Text(label, semanticsLabel: semanticsLabel);
    final Widget? leading = busy
        ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: t.onAccentContainer))
        : (icon == null ? null : Icon(icon, size: 20));
    if (leading == null) return FilledButton(style: style, onPressed: busy ? null : onPressed, child: labelText);
    return FilledButton.icon(style: style, onPressed: busy ? null : onPressed, icon: leading, label: labelText);
  }
}

/// A round icon bubble (Figma activity and category budget rows).
class IconBubble extends StatelessWidget {
  const IconBubble({super.key, required this.icon, this.size = 40, this.background, this.foreground});
  final IconData icon;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background ?? t.secondHigh, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.5, color: foreground ?? t.onSecond),
      ),
    );
  }
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
    } else if (kind == TransactionKind.savings) {
      if (colored) color = StatusColors.ok(context);
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
  const BudgetProgressBar({super.key, required this.progress, this.height = 8, this.onDark = false});
  final BudgetProgress progress;
  final double height;

  /// Use white track colors (for gradient hero cards).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    // Figma: 8px rounded bar on the blue-grey track; on a hero card the
    // track is translucent white.
    final color = onDark ? Colors.white : budgetColor(context, progress.level);
    final track = onDark ? Colors.white.withValues(alpha: 0.3) : context.tokens.secondHigh;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: '${progress.percentUsed} percent of budget used',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        // Length and color ease together (e.g. amber to green when a loan
        // comes back and spending drops). Instant with reduce motion.
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(begin: color, end: color),
          duration: reduced ? Duration.zero : Motion.bar,
          curve: Motion.curve,
          builder: (context, c, _) => TweenAnimationBuilder<double>(
            tween: Tween(begin: reduced ? progress.ratio.clamp(0.0, 1.0).toDouble() : 0, end: progress.ratio.clamp(0.0, 1.0).toDouble()),
            duration: reduced ? Duration.zero : Motion.bar,
            curve: Motion.curve,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: height,
              backgroundColor: track,
              valueColor: AlwaysStoppedAnimation(c ?? color),
            ),
          ),
        ),
      ),
    );
  }
}

/// A category's icon in a round bubble (Figma budget and activity rows:
/// neutral blue-grey bubble, ink icon). Loan categories get the tonal
/// accent, like the loan rows in Activity.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 40});
  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final loan = category?.isLoanRecord ?? false;
    return IconBubble(
      icon: CategoryIcons.of(category?.icon ?? 'other'),
      size: size,
      background: loan ? t.accentContainer : t.secondHigh,
      foreground: loan ? t.onAccentContainer : t.onSecond,
    );
  }
}

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onPrevious,
    required this.onNext,
    this.canGoPrevious = true,
    this.canGoNext,
    this.onPickMonth,
  });
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// False at the earliest month with data (Insights): the button is
  /// greyed out and does nothing.
  final bool canGoPrevious;

  /// Defaults to "not the current month".
  final bool? canGoNext;

  /// When set, tapping the month name opens a picker.
  final VoidCallback? onPickMonth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    final label = DateFormat('MMMM yyyy').format(month);
    final title = Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18));
    // Figma: "‹   November 2026   ›" across the full width.
    return Row(
      children: [
        IconButton(
          onPressed: canGoPrevious ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          tooltip: canGoPrevious ? 'Previous month' : 'No earlier data',
        ),
        Expanded(
          child: onPickMonth == null
              ? title
              : Semantics(
                  button: true,
                  label: 'Choose month, $label',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onPickMonth,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Center(child: title),
                    ),
                  ),
                ),
        ),
        IconButton(
          onPressed: (canGoNext ?? !isCurrent) ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded, size: 28),
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

/// Figma "Dialog": title, message, "Cancel" as an accent text button and
/// the confirm action as a pill (tonal, or red when [destructive]).
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = ctx.tokens;
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? scheme.error : t.accentContainer,
              foregroundColor: destructive ? scheme.onError : t.onAccentContainer,
              minimumSize: const Size(96, 48),
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// A toast (Figma "Snackbar"). Errors are red with a light label.
void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: error ? TextStyle(color: scheme.onError) : null),
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
