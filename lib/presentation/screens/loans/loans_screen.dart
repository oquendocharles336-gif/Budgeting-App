import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/transaction_entry.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/saved_snack.dart';
import '../../widgets/status_badge.dart';
import '../transactions/transaction_form_screen.dart';

/// Every transaction in the "Loan" category, with a Paid button.
///
/// "Paid" only marks the row (with the date). It adds no expense: the
/// transaction itself is already in Activity, so nothing is counted twice.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      body: CascadeScope(
        child: AsyncView<List<TransactionEntry>>(
          value: loans,
          onRetry: () => ref.invalidate(loansProvider),
          loading: const SkeletonList(),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.request_quote_rounded,
                title: 'No loans',
                message: 'Transactions in the "Loan" category show up here, each with a Paid button.',
              );
            }
            final open = list.where((t) => !t.isLoanPaid).toList();
            final paid = list.where((t) => t.isLoanPaid).toList();
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottomInset),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(gradient: AppTheme.heroGradient(scheme), borderRadius: BorderRadius.circular(24)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unpaid loans', style: TextStyle(color: context.tokens.onSecondMuted)),
                      const SizedBox(height: 4),
                      AmountText(
                        open.fold<int>(0, (a, t) => a + t.amount),
                        style: TextStyle(color: context.tokens.accentOnSecond, fontSize: 32, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text('${open.length} unpaid · ${paid.length} paid', style: TextStyle(color: context.tokens.onSecondMuted)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final (i, t) in open.indexed) CascadeIn(index: i, child: _LoanRow(tx: t)),
                if (paid.isNotEmpty) ...[
                  const SectionHeader('Paid'),
                  for (final (i, t) in paid.indexed) CascadeIn(index: open.length + i, child: _LoanRow(tx: t)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoanRow extends ConsumerWidget {
  const _LoanRow({required this.tx});
  final TransactionEntry tx;

  Future<void> _set(BuildContext context, WidgetRef ref, DateTime? paidAt) async {
    final messenger = ScaffoldMessenger.of(context);
    final color = snackTextColor(context);
    final service = ref.read(transactionServiceProvider);
    final before = tx.loanPaidAt;
    try {
      await service.setLoanPaid(tx.id!, paidAt);
      ref.refreshData();
      showSavedSnack(
        messenger,
        text: paidAt == null ? 'Marked unpaid' : 'Marked paid',
        textColor: color,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await service.setLoanPaid(tx.id!, before);
              ref.refreshData();
            } catch (e) {
              debugPrint('Undo failed: $e');
            }
          },
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not update: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cards = ref.watch(cardMapProvider).asDataOrNull ?? const {};
    final account = tx.cardId == null ? 'Cash' : (cards[tx.cardId]?.shortLabel ?? 'Card');
    final fmt = DateFormat('MMM d, yyyy');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => TransactionFormScreen(existing: tx),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tx.description, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${fmt.format(tx.date)} · $account · ${tx.isIncome ? 'Income' : 'Expense'}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                AmountText(
                  tx.amount,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    decoration: tx.isLoanPaid ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: tx.isLoanPaid
                        ? StatusBadge(label: 'Paid ${fmt.format(tx.loanPaidAt!)}', tone: BadgeTone.ok, icon: Icons.check_circle_rounded)
                        : const StatusBadge(label: 'Unpaid', tone: BadgeTone.warning, icon: Icons.schedule_rounded),
                  ),
                ),
                if (tx.isLoanPaid)
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => _set(context, ref, null),
                    child: const Text('Mark unpaid'),
                  )
                else
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
                    onPressed: () => _set(context, ref, DateTime.now()),
                    icon: const Icon(Icons.check_rounded),
                    label: Text('Paid', semanticsLabel: 'Mark ${tx.description} as paid'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
