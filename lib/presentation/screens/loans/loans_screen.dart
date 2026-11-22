import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../data/models/payment_card.dart';
import '../../../data/models/transaction_entry.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/saved_snack.dart';
import '../../widgets/status_badge.dart';
import '../transactions/transaction_form_screen.dart';

/// Every transaction in the "Loan" category, with a Paid button.
///
/// "Paid" asks how it was paid (Cash or an e-wallet) and saves a payment
/// expense on that account: the account goes down and the payment counts in
/// the month's budget, like any transaction with "Paid with". "Mark unpaid"
/// removes the payment again.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key, this.asTab = false});

  /// Inside the "Debts" tab (`DebtsLoansScreen`), which has the app bar.
  final bool asTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider);
    // In the tab, the last row must clear the bottom bar's "+" button.
    final bottomInset = asTab ? 68.0 : MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: asTab ? null : AppBar(title: const Text('Loans')),
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
                message: 'Transactions in the "Loan" category show up here. Tap Paid and choose Cash or E-wallet.',
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

  /// Cash, or one of the e-wallets. Null when dismissed.
  Future<({LoanPayMethod method, int? accountId})?> _pickMethod(BuildContext context, WidgetRef ref) async {
    final accounts = await ref.read(cardsProvider.future);
    final cash = await ref.read(cashBalanceProvider.future);
    if (!context.mounted) return null;
    final wallets = accounts.where((c) => c.type == CardType.ewallet).toList();
    final symbol = ref.read(currencyProvider).symbol;
    return showModalBottomSheet<({LoanPayMethod method, int? accountId})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(tx.isIncome ? 'How did you pay it?' : 'How was it paid back to you?', style: Theme.of(ctx).textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    tx.isIncome
                        ? '${Money.format(tx.amount, symbol: symbol)} is taken from the account you pick and counted in this month\'s budget.'
                        : '${Money.format(tx.amount, symbol: symbol)} comes back to you: it is added to the account you pick.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: Icon(accountIcon(null)),
                  title: const Text('Cash'),
                  subtitle: Text(Money.format(cash, symbol: symbol)),
                  onTap: () => Navigator.pop(ctx, (method: LoanPayMethod.cash, accountId: null)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text('E-wallet', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (wallets.isEmpty)
                  ListTile(
                    enabled: false,
                    leading: Icon(accountIcon(null), color: scheme.onSurfaceVariant),
                    title: const Text('No e-wallets yet'),
                    subtitle: const Text('Add one (e.g. GCash, Maya) in Wallets'),
                  )
                else
                  for (final c in wallets)
                    ListTile(
                      leading: Icon(accountIcon(c), color: Color(c.color)),
                      title: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${c.balanceLabel}: ${Money.format(c.balance, symbol: symbol)}'),
                      onTap: () => Navigator.pop(ctx, (method: LoanPayMethod.ewallet, accountId: c.id)),
                    ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Same "Insufficient balance" question as the transaction form.
  Future<bool> _confirmBalance(BuildContext context, WidgetRef ref, int? accountId) async {
    final int? available;
    try {
      available = await ref.read(transactionServiceProvider).availableBefore(
        kind: TransactionKind.expense,
        accountId: accountId,
      );
    } catch (e) {
      debugPrint('Balance check failed: $e');
      return true;
    }
    if (available == null || tx.amount <= available || !context.mounted) return true;
    final symbol = ref.read(currencyProvider).symbol;
    final name = accountId == null ? 'Cash' : ((ref.read(cardMapProvider).asDataOrNull ?? const {})[accountId]?.nickname ?? 'This e-wallet');
    return confirm(
      context,
      title: 'Insufficient balance',
      message: '$name has ${Money.format(available, symbol: symbol)}, but this loan is '
          '${Money.format(tx.amount, symbol: symbol)}.\n\nMark it paid anyway? The balance will go below zero.',
      confirmLabel: 'Mark paid',
      destructive: false,
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final picked = await _pickMethod(context, ref);
    if (picked == null || !context.mounted) return;
    // Only paying back a loan you received takes money out of an account.
    if (tx.isIncome && (!await _confirmBalance(context, ref, picked.accountId) || !context.mounted)) return;
    final messenger = ScaffoldMessenger.of(context);
    final color = snackTextColor(context);
    final service = ref.read(transactionServiceProvider);
    try {
      await service.payLoan(tx, method: picked.method, accountId: picked.accountId);
      ref.refreshData();
      showSavedSnack(
        messenger,
        text: 'Marked paid with ${picked.method.label}',
        textColor: color,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await service.unpayLoan(tx.id!);
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

  Future<void> _unpay(BuildContext context, WidgetRef ref, TransactionEntry? payment) async {
    final where = payment == null || payment.cardId == null ? 'Cash' : 'the e-wallet';
    final ok = await confirm(
      context,
      title: 'Mark as unpaid?',
      message: tx.isIncome
          ? 'The payment is removed: the money goes back to $where and out of this month\'s budget.'
          : 'The repayment is removed: the money is taken back out of $where.',
      confirmLabel: 'Mark unpaid',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final color = snackTextColor(context);
    final service = ref.read(transactionServiceProvider);
    final method = tx.loanPaidMethod;
    final previous = method == null ? null : (method: method, accountId: payment?.cardId);
    try {
      await service.unpayLoan(tx.id!);
      ref.refreshData();
      showSavedSnack(
        messenger,
        text: 'Marked unpaid',
        textColor: color,
        action: previous == null
            ? null
            : SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await service.payLoan(tx.copyWith(loanPaidAt: () => null), method: previous.method, accountId: previous.accountId);
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
    final payment = (ref.watch(loanPaymentsProvider).asDataOrNull ?? const {})[tx.id];
    final account = tx.cardId == null ? 'Cash' : (cards[tx.cardId]?.shortLabel ?? 'Card');
    final fmt = DateFormat('MMM d, yyyy');
    // "Paid Nov 21, 2026 · Cash" / "· E-wallet (GCash)".
    String paidLabel() {
      final when = 'Paid ${fmt.format(tx.loanPaidAt!)}';
      final method = tx.loanPaidMethod;
      if (method == null) return when;
      if (method == LoanPayMethod.cash) return '$when · Cash';
      final wallet = payment?.cardId == null ? null : cards[payment!.cardId]?.shortLabel;
      return wallet == null ? '$when · E-wallet' : '$when · E-wallet ($wallet)';
    }

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
                        ? StatusBadge(
                      label: paidLabel(),
                      tone: BadgeTone.ok,
                      icon: tx.loanPaidMethod == LoanPayMethod.ewallet
                          ? Icons.account_balance_wallet_rounded
                          : (tx.loanPaidMethod == LoanPayMethod.cash ? Icons.payments_rounded : Icons.check_circle_rounded),
                    )
                        : const StatusBadge(label: 'Unpaid', tone: BadgeTone.warning, icon: Icons.schedule_rounded),
                  ),
                ),
                if (tx.isLoanPaid)
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => _unpay(context, ref, payment),
                    child: const Text('Mark unpaid'),
                  )
                else
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
                    onPressed: () => _pay(context, ref),
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