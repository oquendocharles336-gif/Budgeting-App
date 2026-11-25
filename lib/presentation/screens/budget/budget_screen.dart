import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models/category.dart';
import '../../../domain/budget/budget_calculator.dart';
import '../../../domain/services/app_lock_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/optimistic_providers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/available_balance_card.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final key = Dates.monthKey(month);
    final summary = ref.watch(monthSummaryProvider(key));
    final history = ref.watch(budgetHistoryProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    // Start the work early: when the month changes, load the one before it
    // too (the next tap on "previous" opens instantly).
    ref.listen(selectedMonthProvider, (_, next) {
      ref.read(monthSummaryProvider(Dates.monthKey(Dates.previousMonth(next))).future).ignore();
    });

    return Scaffold(
      appBar: AppBar(title: Text('Budget', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, 100),
        children: [
          MonthSwitcher(month: month, onPrevious: notifier.previous, onNext: notifier.next),
          AsyncView<MonthSummary>(
            value: summary,
            onRetry: () => ref.refreshData(),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.xs),
                _OverallCard(summary: s, onEdit: () => _editBudget(context, ref, key, null, s.overall.budget)),
                if (s.loansReturned > 0) ...[
                  const SizedBox(height: Space.md),
                  _LoansReturnedRow(amount: s.loansReturned),
                ],
                SectionHeader(
                  'Category budgets',
                  actionLabel: 'Add',
                  onAction: () => _addCategoryBudget(context, ref, key, s),
                ),
                if (s.categoryRows.isEmpty)
                  const AppCard(
                    child: Text('No spending yet this month. Add a category budget to keep an eye on food, transport and more.'),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.xs),
                      child: Column(
                        children: [
                          for (final (i, r) in s.categoryRows.indexed)
                            CascadeIn(
                              key: ValueKey('budget-${r.category.id}'),
                              index: i,
                              child: _CategoryRow(
                                row: r,
                                onTap: () => _editBudget(context, ref, key, r.category, r.progress.budget),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: Space.lg),
                // Income goes into an account, so it raises what's available to spend.
                AvailableBalanceCard(
                  incomeLabel: 'Income in ${DateFormat('MMMM').format(month)}:',
                  income: s.income,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AsyncView<List<BudgetHistoryItem>>(
            value: history,
            loading: const SizedBox.shrink(),
            data: (items) {
              final past = items.where((i) => i.month.isBefore(Dates.monthStart(DateTime.now()))).toList();
              if (past.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader('History'),
                  Card(
                    child: Column(
                      children: [
                        for (final h in past)
                          ListTile(
                            onTap: () => notifier.set(h.month),
                            title: Text(DateFormat('MMMM yyyy').format(h.month)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: BudgetProgressBar(progress: h.progress, height: 6),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${h.progress.percentUsed}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: budgetColor(context, h.progress.level),
                                    )),
                                Text(
                                  h.progress.remaining >= 0 ? 'under' : 'over',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addCategoryBudget(BuildContext context, WidgetRef ref, String monthKey, MonthSummary s) async {
    final categories = await ref.read(categoriesProvider.future);
    final withBudget = s.categoryRows.where((r) => r.progress.hasBudget).map((r) => r.category.id).toSet();
    final options = categories.where((c) => !c.isIncome && !withBudget.contains(c.id)).toList();
    if (!context.mounted) return;
    if (options.isEmpty) {
      showSnack(context, 'Every category already has a budget.');
      return;
    }
    final picked = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in options)
              ListTile(
                leading: CategoryAvatar(category: c, size: 36),
                title: Text(c.name),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) await _editBudget(context, ref, monthKey, picked, 0);
  }

  Future<void> _editBudget(BuildContext context, WidgetRef ref, String monthKey, Category? category, int current) async {
    final symbol = ref.read(currencyProvider).symbol;
    final controller = TextEditingController(text: current > 0 ? Money.toInput(current) : '');
    final formKey = GlobalKey<FormState>();
    final monthName = DateFormat('MMMM').format(Dates.parseMonthKey(monthKey));

    // Returns: amount (>0) to save, 0 to remove, null = cancelled.
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category == null ? 'Budget for $monthName' : '${category.name} budget'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(labelText: 'Amount', prefixText: '$symbol '),
            validator: validateAmount,
          ),
        ),
        actions: [
          if (current > 0) TextButton(onPressed: () => Navigator.pop(ctx, 0), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, Money.parse(controller.text));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    // Optimistic: show the new amount now, save, then reconcile. If the
    // write fails, the old amount comes back with a message.
    final pending = ref.read(pendingBudgetsProvider.notifier);
    final key = pending.put(monthKey, category?.id, result == 0 ? null : result);
    try {
      await ref.read(budgetRepositoryProvider).setBudget(monthKey, category?.id, result == 0 ? null : result);
    } catch (e) {
      pending.clear(key);
      if (context.mounted) showSnack(context, 'Couldn\'t save the budget, so it was put back: $e', error: true);
      return;
    }
    ref.refreshData();
    pending.clear(key);
    if (result > 0) {
      try {
        await LockGuard.run(() => ref.read(notificationServiceProvider).requestPermission());
        await ref.read(budgetAlertServiceProvider).checkMonth(Dates.parseMonthKey(monthKey));
      } catch (e) {
        debugPrint('Budget alert check failed: $e');
      }
    }
  }
}

class _OverallCard extends ConsumerWidget {
  const _OverallCard({required this.summary, required this.onEdit});
  final MonthSummary summary;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = summary.overall;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrent = Dates.monthKey(summary.month) == Dates.monthKey(now);
    final avg = BudgetCalculator.averageDaily(spent: p.spent, month: summary.month, now: now);
    final safe = BudgetCalculator.safeDailySpend(budget: p.budget, spent: p.spent, month: summary.month, now: now);
    final projected = BudgetCalculator.projectedMonthEnd(spent: p.spent, month: summary.month, now: now);

    if (!p.hasBudget) {
      return AppCard(
        child: Column(
          children: [
            IconBubble(icon: Icons.flag_outlined, size: 56, background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer),
            const SizedBox(height: Space.md),
            Text('No monthly budget set', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xxs),
            Text('Spent so far: ${formatMoney(ref, p.spent)}', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Space.lg),
            FilledButton(onPressed: onEdit, child: const Text('Set a budget')),
          ],
        ),
      );
    }

    final color = budgetColor(context, p.level);
    final t = context.tokens;
    final warn = p.level == BudgetLevel.warning || p.level == BudgetLevel.exceeded;
    return AppCard(
      onTap: onEdit,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.remaining >= 0 ? 'Remaining' : 'Over budget',
                  style: TextStyle(color: t.onSecondMuted, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Text('${p.percentUsed}% used', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(width: Space.xs),
              Icon(Icons.edit_outlined, size: 18, color: t.onSecond, semanticLabel: 'Edit budget'),
            ],
          ),
          const SizedBox(height: Space.xxs),
          // Counts up or down to the new amount (450 ms, e.g. after a loan
          // comes back). Instant with reduce motion.
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: p.remaining.abs(), end: p.remaining.abs()),
            duration: Cascade.reduced(context) ? Duration.zero : Motion.countUp,
            curve: Motion.curve,
            builder: (context, value, _) => AmountText(
              value,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: p.remaining < 0 ? color : t.onSecond),
            ),
          ),
          const SizedBox(height: Space.md),
          BudgetProgressBar(progress: p),
          const SizedBox(height: Space.sm),
          Text(
            '${formatMoney(ref, p.spent)} spent of ${formatMoney(ref, p.budget)}',
            style: TextStyle(color: t.onSecond, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (warn) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
              decoration: BoxDecoration(
                color: p.level == BudgetLevel.exceeded ? t.dangerContainer : t.warningContainer,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      p.level == BudgetLevel.exceeded ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                      size: 20,
                      color: p.level == BudgetLevel.exceeded ? t.onDangerContainer : t.onWarningContainer,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      p.level == BudgetLevel.exceeded ? 'Budget used up.' : 'Heads up: over 80% used.',
                      style: TextStyle(
                        color: p.level == BudgetLevel.exceeded ? t.onDangerContainer : t.onWarningContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          Divider(height: 1, color: t.outline),
          const SizedBox(height: Space.md),
          Row(
            children: [
              _Stat(label: 'Avg / day', value: formatMoney(ref, avg)),
              if (isCurrent) _Stat(label: 'Safe / day', value: formatMoney(ref, safe)),
              if (isCurrent) _Stat(label: 'Projected', value: formatMoney(ref, projected)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: context.tokens.onSecondMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.tokens.onSecond)),
          ],
        ),
      );
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({required this.row, required this.onTap});
  final CategoryBudgetRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = row.progress;
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
        child: Row(
          children: [
            CategoryAvatar(category: row.category, size: 40),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(row.category.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: t.onSecond)),
                      ),
                      Text(
                        p.hasBudget ? '${formatMoney(ref, p.spent)} / ${formatMoney(ref, p.budget)}' : formatMoney(ref, p.spent),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.onSecond),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  if (p.hasBudget)
                    BudgetProgressBar(progress: p, height: 6)
                  else
                    Text('No budget · tap to set', style: TextStyle(color: t.onSecondMuted, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Loans returned this month  -P1,000.00  (i)": loans you gave and got
/// back this month, which aren't counted as spending. Tap for why.
class _LoansReturnedRow extends ConsumerWidget {
  const _LoansReturnedRow({required this.amount});
  final int amount;

  void _explain(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final t = ctx.tokens;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Loans returned', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: t.onSecond)),
                  const SizedBox(height: Space.md),
                  Text(
                    'Money you lent and got back in the same month isn\'t counted as spending.',
                    style: TextStyle(color: t.onSecond, fontSize: 15.5, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    'If it comes back in a later month, it stays counted in the month you lent it. '
                    'Marking a loan unpaid again brings the deduction back.',
                    style: TextStyle(color: t.onSecond, fontSize: 15.5, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: Space.xl),
                  TonalPillButton(label: 'Got it', expand: true, onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ok = t.onSuccessContainer;
    final background = t.successContainer;
    return Semantics(
      button: true,
      label: 'Loans returned this month, minus ${formatMoney(ref, amount)}. Tap to learn more.',
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: () => _explain(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
              child: Row(
                children: [
                  Icon(Icons.handshake_outlined, color: ok, size: 24),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      'Loans returned this month',
                      style: TextStyle(color: Contrast.ensure(t.onSecond, background), fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text('\u2212${formatMoney(ref, amount)}', style: TextStyle(color: ok, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(width: Space.sm),
                  Icon(Icons.info_outline_rounded, size: 20, color: Contrast.ensure(t.onSecondMuted, background)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
