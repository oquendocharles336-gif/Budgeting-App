import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../data/models/debt.dart';
import '../../../domain/debt/interest_calculator.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'debt_form_screen.dart';

class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({super.key, required this.debtId});
  final int debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider);
    final payments = ref.watch(debtPaymentsProvider(debtId));
    final scheme = Theme.of(context).colorScheme;

    return AsyncView<List<DebtStatus>>(
      value: debts,
      data: (list) {
        final matches = list.where((d) => d.debt.id == debtId);
        if (matches.isEmpty) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Debt not found'));
        final s = matches.first;
        final d = s.debt;
        final symbol = ref.watch(currencyProvider).symbol;
        return Scaffold(
          appBar: AppBar(
            title: Text(d.creditor),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtFormScreen(existing: d))),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final ok = await confirm(context, title: 'Delete this debt?', message: 'Its payment history is deleted too.');
                  if (!ok) return;
                  await ref.read(debtServiceProvider).delete(debtId);
                  ref.refreshData();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
          floatingActionButton: s.isSettled
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _recordPayment(context, ref, s),
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('Record payment'),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.isSettled ? 'Paid off' : 'Remaining', style: TextStyle(color: scheme.onSurfaceVariant)),
                    AmountText(s.remaining, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: s.progress,
                        minHeight: 10,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(StatusColors.ok(context)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _row('Type', d.type.label),
                    if (d.lenderLabel != null) _row('Borrowed from', d.lenderLabel!),
                    _row('Total', Money.format(d.totalAmount, symbol: symbol)),
                    _row('Paid so far', Money.format(s.paid, symbol: symbol)),
                    if (d.dueDate != null) _row('Due', DateFormat('MMMM d, yyyy').format(d.dueDate!)),
                    if (d.interestRateBp != null)
                      _row(
                        'Interest',
                        '${(d.interestRateBp! / 100).toStringAsFixed(2)}% ${d.interestPeriod.label} · ${d.interestType.label.toLowerCase()}',
                      ),
                    if (d.termMonths != null) _row('Term', '${d.termMonths} monthly payments'),
                    if (d.notes != null) _row('Notes', d.notes!),
                  ],
                ),
              ),
              if (InterestCalculator.forStatus(s) case final q? when q.dueThisMonth > 0) ...[
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Get ready this month', style: TextStyle(color: scheme.onSurfaceVariant)),
                      Text(Money.format(q.dueThisMonth, symbol: symbol), style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      _row('Interest this month', Money.format(q.interestThisMonth, symbol: symbol)),
                      if (q.monthlyPayment != null)
                        _row('Monthly payment', Money.format(q.monthlyPayment!, symbol: symbol)),
                      if (q.totalInterest != null)
                        _row('Total interest', Money.format(q.totalInterest!, symbol: symbol)),
                      const SizedBox(height: 4),
                      Text(
                        q.monthlyPayment == null
                            ? 'Interest only. Add the number of payments (Edit) to include the principal.'
                            : d.interestType == InterestType.compound
                                ? 'Compound: interest is on what you still owe, so it goes down as you pay.'
                                : 'Simple: interest is on the amount you borrowed.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      Text(
                        'Estimate. Your lender\'s statement is the final amount.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(debtServiceProvider).setPaid(debtId, !d.isPaid, currencySymbol: symbol);
                  ref.refreshData();
                },
                icon: Icon(d.isPaid ? Icons.undo_rounded : Icons.check_circle_outline_rounded),
                label: Text(d.isPaid ? 'Mark as not paid' : 'Mark as paid'),
              ),
              const SectionHeader('Payments'),
              AsyncView<List<DebtPayment>>(
                value: payments,
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No payments recorded yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : Card(
                        child: Column(
                          children: [
                            for (final p in list)
                              ListTile(
                                leading: const Icon(Icons.payments_outlined),
                                title: Text(Money.format(p.amount, symbol: symbol)),
                                subtitle: Text([
                                  DateFormat('MMM d, yyyy').format(p.date),
                                  if (p.note != null) p.note!,
                                ].join(' · ')),
                                trailing: IconButton(
                                  tooltip: 'Delete payment',
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    final ok = await confirm(context, title: 'Delete payment?', message: 'The balance goes back up.');
                                    if (!ok) return;
                                    await ref.read(debtServiceProvider).deletePayment(p, currencySymbol: symbol);
                                    ref.refreshData();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(label)),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Future<void> _recordPayment(BuildContext context, WidgetRef ref, DebtStatus s) async {
    final amount = TextEditingController(text: Money.toInput(s.remaining));
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var date = DateTime.now();
    final symbol = ref.read(currencyProvider).symbol;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Record payment', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(labelText: 'Amount', prefixText: '$symbol '),
                  validator: (v) {
                    final err = validateAmount(v);
                    if (err != null) return err;
                    if (Money.parse(v!)! > s.remaining) return 'More than the remaining ${Money.format(s.remaining, symbol: symbol)}';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text(DateFormat('MMMM d, yyyy').format(date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
                  },
                  child: const Text('Save payment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      await ref.read(debtServiceProvider).addPayment(
            DebtPayment(
              debtId: debtId,
              amount: Money.parse(amount.text)!,
              date: date,
              note: note.text.trim().isEmpty ? null : note.text.trim(),
            ),
            currencySymbol: symbol,
          );
      ref.refreshData();
    }
    // Controllers aren't disposed here: the sheet may still be animating
    // closed and using them. They're garbage-collected with this closure.
  }
}
