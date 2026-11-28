import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/debt.dart';
import '../../../domain/debt/debt_reminder.dart';
import '../../../domain/debt/interest_calculator.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import 'debt_detail_screen.dart';
import 'debt_form_screen.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key, this.asTab = false});
  final bool asTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DebtsLoansScreen(asTab: asTab, initialTab: 0);
}

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key, this.asTab = false});
  final bool asTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DebtsLoansScreen(asTab: asTab, initialTab: 1);
}

class DebtsLoansScreen extends ConsumerStatefulWidget {
  const DebtsLoansScreen({super.key, this.asTab = false, this.initialTab = 0});
  final bool asTab;
  final int initialTab;

  @override
  ConsumerState<DebtsLoansScreen> createState() => _DebtsLoansScreenState();
}

class _DebtsLoansScreenState extends ConsumerState<DebtsLoansScreen> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(debtsProvider);
    void openAdd() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DebtFormScreen(initialDirection: _tab == 0 ? DebtDirection.borrowed : DebtDirection.lent),
        ));
    final bottomInset = widget.asTab ? 68.0 : MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: widget.asTab ? null : AppBar(title: const Text('Debts & Loans')),
      floatingActionButton: widget.asTab
          ? null
          : FloatingActionButton.extended(
              tooltip: _tab == 0 ? 'Add debt' : 'Add loan',
              onPressed: openAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(_tab == 0 ? 'Add debt' : 'Add loan'),
            ),
      body: CascadeScope(
        child: AsyncView<List<DebtStatus>>(
          value: debts,
          onRetry: () => ref.invalidate(debtsProvider),
          data: (allList) {
            final list = allList.where((d) => _tab == 0 ? d.debt.isBorrowed : d.debt.isLent).toList();
            final open = list.where((d) => !d.isSettled).toList();
            final paid = list.where((d) => d.isSettled).toList();
            final total = open.fold<int>(0, (a, d) => a + d.remaining);
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 100 + bottomInset),
              children: [
                PillTabs(
                  labels: ['Borrowed (I owe)', 'Lent (Owed to me)'],
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 16),
                HeroCard(
                  label: _tab == 0 ? 'Total outstanding debt' : 'Total outstanding loans',
                  value: AmountText(total),
                  caption: '${open.length} open · ${paid.length} paid',
                ),
                const SizedBox(height: 16),
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.handshake_rounded,
                    title: _tab == 0 ? 'No debts' : 'No loans lent',
                    message: _tab == 0
                        ? 'Track money you owe: loans, installments, or bills.'
                        : 'Lent someone money? Track it here and tap Paid when you get it back.',
                    action: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: openAdd,
                      child: Text(_tab == 0 ? '+ Add debt' : '+ Add loan'),
                    ),
                  )
                else ...[
                  for (final (i, d) in open.indexed) CascadeIn(index: i, child: _DebtCard(status: d)),
                  if (paid.isNotEmpty) ...[
                    const SectionHeader('Paid off'),
                    for (final (i, d) in paid.indexed) CascadeIn(index: open.length + i, child: _DebtCard(status: d)),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DebtCard extends ConsumerWidget {
  const _DebtCard({required this.status});
  final DebtStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = status.debt;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final overdue = status.isOverdue(now);
    final quote = InterestCalculator.forStatus(status);
    String? dueText;
    String? soonText;
    final missed = status.overdueSince(now);
    final next = status.nextDue(now);
    if (missed != null) {
      soonText = DebtReminders.rowLabel(missed, now);
      dueText = soonText ?? 'Overdue since ${DateFormat('MMM d').format(missed)}';
    } else if (next != null) {
      soonText = DebtReminders.rowLabel(next, now);
      dueText = soonText ?? 'Next: ${DateFormat('MMM d').format(next)}';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: d.id!))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.creditor, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        [d.type.label, ?d.lenderLabel, d.isNew ? 'In expenses' : 'Reminder only'].join(' · '),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (status.isSettled)
                  Icon(Icons.check_circle_rounded, color: StatusColors.ok(context))
                else
                  AmountText(status.remaining, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: status.progress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(StatusColors.ok(context)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatMoney(ref, status.paid)} paid of ${formatMoney(ref, d.totalAmount)}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ),
                if (dueText != null)
                  Text(
                    dueText,
                    style: TextStyle(
                      color: overdue
                          ? scheme.error
                          : soonText != null
                              ? StatusColors.warning(context)
                              : scheme.onSurfaceVariant,
                      fontWeight: soonText != null ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
            if (quote != null && quote.dueThisMonth > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Prepare ${formatMoney(ref, quote.dueThisMonth)} this month'
                '${quote.monthlyPayment == null ? ' (interest)' : ''}',
                style: TextStyle(color: context.tokens.accentOnSecond, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
