import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models/category.dart';
import '../../../domain/budget/budget_calculator.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final key = Dates.monthKey(month);
    final summary = ref.watch(monthSummaryProvider(key));
    final history = ref.watch(budgetHistoryProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Budget')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          MonthSwitcher(month: month, onPrevious: notifier.previous, onNext: notifier.next),
          AsyncView<MonthSummary>(
            value: summary,
            onRetry: () => ref.refreshData(),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OverallCard(summary: s, onEdit: () => _editBudget(context, ref, key, null, s.overall.budget)),
                const SizedBox(height: 8),
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
                    child: Column(
                      children: [
                        for (final r in s.categoryRows)
                          _CategoryRow(
                            row: r,
                            onTap: () => _editBudget(context, ref, key, r.category, r.progress.budget),
                          ),
                      ],
                    ),
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
    await ref.read(budgetRepositoryProvider).setBudget(monthKey, category?.id, result == 0 ? null : result);
    if (result > 0) {
      await ref.read(notificationServiceProvider).requestPermission();
      await ref.read(budgetAlertServiceProvider).checkMonth(Dates.parseMonthKey(monthKey));
    }
    ref.refreshData();
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
            Icon(Icons.flag_rounded, size: 36, color: scheme.primary),
            const SizedBox(height: 8),
            Text('No monthly budget set', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Spent so far: ${formatMoney(ref, p.spent)}', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onEdit, child: const Text('Set a budget')),
          ],
        ),
      );
    }

    final color = budgetColor(context, p.level);
    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.remaining >= 0 ? 'Remaining' : 'Over budget', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
              Text('${p.percentUsed}% used', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              Icon(Icons.edit_rounded, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
          AmountText(
            p.remaining.abs(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: p.remaining < 0 ? color : null),
          ),
          const SizedBox(height: 12),
          BudgetProgressBar(progress: p),
          const SizedBox(height: 8),
          Text('${formatMoney(ref, p.spent)} spent of ${formatMoney(ref, p.budget)}'),
          if (p.level == BudgetLevel.warning || p.level == BudgetLevel.exceeded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(p.level == BudgetLevel.exceeded ? Icons.error_rounded : Icons.warning_amber_rounded, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.level == BudgetLevel.exceeded ? 'Budget used up.' : 'Heads up: over 80% used.',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 28),
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
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            CategoryAvatar(category: row.category, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(row.category.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(
                        p.hasBudget ? '${formatMoney(ref, p.spent)} / ${formatMoney(ref, p.budget)}' : formatMoney(ref, p.spent),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (p.hasBudget)
                    BudgetProgressBar(progress: p, height: 6)
                  else
                    Text('No budget · tap to set', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
