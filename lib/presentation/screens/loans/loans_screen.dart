import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/dates.dart';
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

/// Every transaction in the "Loan" category, split into Unpaid and Paid.
///
/// "Paid" opens a sheet that asks how it was paid back (Cash or an
/// e-wallet) and on which day, with a live preview of the balance and the
/// budget. A loan you gave that comes back in the same month you lent it
/// is taken out of that month's spending; one that comes back later stays
/// counted in the month it was lent. "Mark unpaid" undoes the repayment.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key, this.asTab = false});

  /// Inside the "Debts" tab (`DebtsLoansScreen`), which has the app bar.
  final bool asTab;

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  bool _showPaid = false;

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansProvider);
    // In the tab, the last row must clear the bottom bar's "+" button.
    final bottomInset = widget.asTab ? 68.0 : MediaQuery.viewPaddingOf(context).bottom;
    final padding = EdgeInsets.fromLTRB(16, 8, 16, 32 + bottomInset);
    return Scaffold(
      appBar: widget.asTab ? null : AppBar(title: const Text('Loans')),
      body: CascadeScope(
        child: AsyncView<List<TransactionEntry>>(
          value: loans,
          onRetry: () => ref.invalidate(loansProvider),
          loading: _LoansSkeleton(padding: padding),
          data: (list) {
            if (list.isEmpty) return const _NoLoans();
            final open = list.where((t) => !t.isLoanPaid).toList();
            final paid = list.where((t) => t.isLoanPaid).toList();
            final shown = _showPaid ? paid : open;
            final reduced = Cascade.reduced(context);
            return ListView(
              padding: padding,
              children: [
                _Hero(open: open, paid: paid),
                const SizedBox(height: 12),
                _LoanTabs(
                  unpaid: open.length,
                  paid: paid.length,
                  showPaid: _showPaid,
                  onChanged: (v) => setState(() => _showPaid = v),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 200),
                  child: Column(
                    key: ValueKey(_showPaid),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (shown.isEmpty)
                        AppCard(
                          child: Text(
                            _showPaid ? 'No paid loans yet.' : 'Nothing unpaid. Every loan has been paid back.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        )
                      else
                        for (final (i, t) in shown.indexed)
                          CascadeIn(key: ValueKey('loan-${t.id}'), index: i, child: _LoanRow(tx: t)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "Unpaid loans ₱2,500.00 · 2 unpaid · 2 paid" and, when loans came back
/// this month, how much that took off this month's budget.
class _Hero extends ConsumerWidget {
  const _Hero({required this.open, required this.paid});
  final List<TransactionEntry> open;
  final List<TransactionEntry> paid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final t = context.tokens;
    final now = DateTime.now();
    final deducted = paid
        .where((l) => l.isLoanCancelledByRepayment && l.date.year == now.year && l.date.month == now.month)
        .fold<int>(0, (a, l) => a + l.amount);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppTheme.heroGradient(scheme), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unpaid loans', style: TextStyle(color: t.onSecondMuted)),
          const SizedBox(height: 4),
          AmountText(
            open.fold<int>(0, (a, l) => a + l.amount),
            style: TextStyle(color: t.accentOnSecond, fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('${open.length} unpaid · ${paid.length} paid', style: TextStyle(color: t.onSecondMuted)),
          if (deducted > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.main.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Icon(Icons.pie_chart_rounded, size: 16, color: t.onSecond)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${formatMoney(ref, deducted)} deducted from ${DateFormat('MMMM').format(now)}\'s budget',
                      style: TextStyle(color: t.onSecond, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-segment switch: "Unpaid · 2" | "Paid · 2".
class _LoanTabs extends StatelessWidget {
  const _LoanTabs({required this.unpaid, required this.paid, required this.showPaid, required this.onChanged});
  final int unpaid;
  final int paid;
  final bool showPaid;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget segment(String label, bool selected, VoidCallback onTap) => Expanded(
          child: Semantics(
            selected: selected,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: AnimatedContainer(
                duration: Cascade.reduced(context) ? Duration.zero : const Duration(milliseconds: 200),
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? t.accent.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? t.accentOnSecond : t.onSecondMuted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.second,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.outline),
      ),
      child: Row(
        children: [
          segment('Unpaid · $unpaid', !showPaid, () => onChanged(false)),
          segment('Paid · $paid', showPaid, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// No loans at all: explain the "Loan" category and offer to add one.
class _NoLoans extends ConsumerWidget {
  const _NoLoans();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final categories = await ref.read(categoriesProvider.future);
    final loan = categories.where((c) => c.isLoanRecord || c.name.toLowerCase() == 'loan').firstOrNull;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TransactionFormScreen(initialCategoryId: loan?.id),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => EmptyState(
        icon: Icons.handshake_rounded,
        title: 'No loans yet',
        message: 'Lent someone money? Add it in the "Loan" category and tap Paid when you get it back.',
        action: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a loan'),
        ),
      );
}

/// Loading: the shape of the real screen (hero, tabs, rows).
class _LoansSkeleton extends StatelessWidget {
  const _LoansSkeleton({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          child: Skeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SkeletonBox(height: 120, radius: 24),
                const SizedBox(height: 12),
                const SkeletonBox(height: 44, radius: 999),
                const SizedBox(height: 12),
                for (var i = 0; i < 3; i++)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: _SkeletonLoanRow(),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _SkeletonLoanRow extends StatelessWidget {
  const _SkeletonLoanRow();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: context.tokens.secondHigh),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 160, height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 110, height: 12),
            SizedBox(height: 10),
            SkeletonBox(width: 70, height: 20, radius: 999),
            SizedBox(height: 6),
            Align(alignment: Alignment.centerRight, child: SkeletonBox(width: 96, height: 40, radius: 999)),
          ],
        ),
      );
}

/// What the "Mark as paid" sheet returns.
typedef _PayChoice = ({LoanPayMethod method, int? accountId, String accountName, DateTime? paidAt});

class _LoanRow extends ConsumerStatefulWidget {
  const _LoanRow({required this.tx});
  final TransactionEntry tx;

  @override
  ConsumerState<_LoanRow> createState() => _LoanRowState();
}

class _LoanRowState extends ConsumerState<_LoanRow> {
  bool _saving = false;

  TransactionEntry get tx => widget.tx;

  /// Same "Insufficient balance" question as the transaction form.
  Future<bool> _confirmBalance(int? accountId, String name) async {
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
    if (available == null || tx.amount <= available || !mounted) return true;
    final symbol = ref.read(currencyProvider).symbol;
    return confirm(
      context,
      title: 'Insufficient balance',
      message: '$name has ${Money.format(available, symbol: symbol)}, but this loan is '
          '${Money.format(tx.amount, symbol: symbol)}.\n\nMark it paid anyway? The balance will go below zero.',
      confirmLabel: 'Mark paid',
      destructive: false,
    );
  }

  /// The overall "spent" of [month], or null if it can't be read.
  Future<int?> _spentIn(DateTime month) async {
    try {
      return (await ref.read(monthSummaryProvider(Dates.monthKey(month)).future)).overall.spent;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pay() async {
    final picked = await showModalBottomSheet<_PayChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MarkPaidSheet(loan: tx),
    );
    if (picked == null || !mounted) return;
    await _save(picked);
  }

  Future<void> _save(_PayChoice picked) async {
    // Only paying back a loan you received takes money out of an account.
    if (tx.isIncome && (!await _confirmBalance(picked.accountId, picked.accountName) || !mounted)) return;
    final messenger = ScaffoldMessenger.of(context);
    final color = snackTextColor(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final service = ref.read(transactionServiceProvider);
    // Undo can run after this row has moved to the other tab (disposed).
    final refresh = ref.read(dataRevisionProvider.notifier).bump;
    final symbol = ref.read(currencyProvider).symbol;
    final paidOn = picked.paidAt ?? DateTime.now();
    final cancels = tx.isExpense && Dates.monthKey(paidOn) == Dates.monthKey(tx.date);
    // The month whose budget changes: the lent month when the loan cancels
    // out, the payment month when you pay back a loan you received.
    final budgetMonth = tx.isIncome ? paidOn : tx.date;
    final spentBefore = (cancels || tx.isIncome) ? await _spentIn(budgetMonth) : null;
    if (!mounted) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      await service.payLoan(tx, method: picked.method, accountId: picked.accountId, paidAt: picked.paidAt);
      refresh();
      final monthName = DateFormat('MMMM').format(budgetMonth);
      final String detail;
      if (spentBefore != null) {
        final after = cancels ? spentBefore - tx.amount : spentBefore + tx.amount;
        detail = cancels
            ? '$monthName spent back to ${Money.format(after, symbol: symbol)}'
            : '$monthName spent now ${Money.format(after, symbol: symbol)}';
      } else {
        detail = tx.isExpense ? 'Still counted in ${DateFormat('MMMM').format(tx.date)}\'s budget' : 'Counted in $monthName\'s budget';
      }
      showSavedSnack(
        messenger,
        text: 'Marked paid with ${picked.accountName} · $detail',
        textColor: color,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await service.unpayLoan(tx.id!, loan: tx.copyWith(loanPaidAt: () => paidOn));
              refresh();
              showSavedSnack(
                messenger,
                text: cancels ? 'Undone · Counted in $monthName\'s budget again' : 'Undone',
                textColor: color,
              );
            } catch (e) {
              debugPrint('Undo failed: $e');
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('Mark paid failed: $e');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: errorColor,
          content: const Text('Couldn\'t mark it paid, so nothing changed.'),
          action: SnackBarAction(label: 'Try again', onPressed: () => _save(picked)),
        ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unpay(String where) async {
    final symbol = ref.read(currencyProvider).symbol;
    final amount = Money.format(tx.amount, symbol: symbol);
    final paidMonth = DateFormat('MMMM').format(tx.loanPaidAt!);
    final lentMonth = DateFormat('MMMM').format(tx.date);
    final String message;
    if (tx.isIncome) {
      message = 'The payment is removed: $amount goes back to $where and out of $paidMonth\'s budget.';
    } else if (tx.isLoanCancelledByRepayment) {
      message = 'The repayment is removed: $amount is taken back out of $where, '
          'and the loan counts in $lentMonth\'s budget again.';
    } else {
      message = 'The repayment is removed: $amount is taken back out of $where. '
          '$lentMonth\'s budget doesn\'t change.';
    }
    final ok = await confirm(context, title: 'Mark as unpaid?', message: message, confirmLabel: 'Mark unpaid', destructive: false);
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final color = snackTextColor(context);
    final service = ref.read(transactionServiceProvider);
    final refresh = ref.read(dataRevisionProvider.notifier).bump;
    final method = tx.loanPaidMethod;
    final payment = (ref.read(loanPaymentsProvider).asDataOrNull ?? const {})[tx.id];
    final previous = method == null
        ? null
        : (method: method, accountId: payment?.cardId, paidAt: tx.loanPaidAt);
    setState(() => _saving = true);
    try {
      await service.unpayLoan(tx.id!, loan: tx);
      refresh();
      showSavedSnack(
        messenger,
        text: tx.isLoanCancelledByRepayment ? 'Marked unpaid · Counted in $lentMonth\'s budget again' : 'Marked unpaid',
        textColor: color,
        action: previous == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  try {
                    await service.payLoan(
                      tx.copyWith(loanPaidAt: () => null),
                      method: previous.method,
                      accountId: previous.accountId,
                      paidAt: previous.paidAt,
                    );
                    refresh();
                  } catch (e) {
                    debugPrint('Undo failed: $e');
                  }
                },
              ),
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Could not update: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cards = ref.watch(cardMapProvider).asDataOrNull ?? const {};
    final payment = (ref.watch(loanPaymentsProvider).asDataOrNull ?? const {})[tx.id];
    final account = tx.cardId == null ? 'Cash' : (cards[tx.cardId]?.nickname ?? 'Card');
    final fullDate = DateFormat('MMM d, yyyy');
    final shortDate = DateFormat('MMM d');
    final month = DateFormat('MMM');
    final now = DateTime.now();
    final paid = tx.isLoanPaid;

    // Where the repayment went: "Cash", "GCash"...
    final paidWith = !paid || tx.loanPaidMethod == LoanPayMethod.cash || payment?.cardId == null
        ? (tx.loanPaidMethod == LoanPayMethod.ewallet ? 'E-wallet' : 'Cash')
        : (cards[payment!.cardId]?.nickname ?? 'E-wallet');

    // One muted line under the chips that says how the budget sees it.
    final String? hint;
    if (tx.isIncome) {
      hint = paid
          ? 'Payment counted in ${month.format(tx.loanPaidAt!)}'
          : 'Paying it back counts in that month\'s budget';
    } else if (paid) {
      hint = tx.isLoanCancelledByRepayment ? null : 'Counted in ${month.format(tx.date)}';
    } else {
      hint = Dates.monthKey(tx.date) == Dates.monthKey(now)
          ? 'Counts in ${month.format(tx.date)} budget · Repaid this month cancels it'
          : 'Already counted in ${month.format(tx.date)}';
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tx.description, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${tx.isIncome ? 'Borrowed' : 'Lent'} ${fullDate.format(tx.date)} · $account',
                        style: TextStyle(color: t.onSecondMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AmountText(
                  tx.amount,
                  // Paid amounts are muted, not struck through.
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: paid ? t.onSecondMuted : t.onSecond),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (paid) ...[
                  StatusBadge(
                    label: 'Paid ${shortDate.format(tx.loanPaidAt!)} · $paidWith',
                    tone: BadgeTone.ok,
                    icon: Icons.check_circle_rounded,
                  ),
                  if (tx.isLoanCancelledByRepayment)
                    const StatusBadge(label: 'Not in budget', tone: BadgeTone.neutral, icon: Icons.remove_circle_outline_rounded),
                ] else
                  const StatusBadge(label: 'Unpaid', tone: BadgeTone.warning, icon: Icons.schedule_rounded),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint, style: TextStyle(color: t.onSecondMuted, fontSize: 12)),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: paid
                  ? TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: _saving ? null : () => _unpay(paidWith),
                      child: const Text('Mark unpaid'),
                    )
                  : FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
                      onPressed: _saving ? null : _pay,
                      icon: _saving
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: Text('Paid', semanticsLabel: 'Mark ${tx.description} as paid'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "How was it paid back to you?": pick the account and the day, see what
/// changes, then confirm.
class _MarkPaidSheet extends ConsumerStatefulWidget {
  const _MarkPaidSheet({required this.loan});
  final TransactionEntry loan;

  @override
  ConsumerState<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends ConsumerState<_MarkPaidSheet> {
  /// null = Cash.
  int? _accountId;

  /// The day it was paid back (today by default).
  DateTime _day = Dates.startOfDay(DateTime.now());

  TransactionEntry get loan => widget.loan;

  bool get _isToday => Dates.sameDay(_day, DateTime.now());

  Future<void> _pickDay() async {
    final today = Dates.startOfDay(DateTime.now());
    final first = Dates.startOfDay(loan.date);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: first.isAfter(today) ? today : first,
      lastDate: today,
      helpText: 'Paid on',
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  /// null when today (save with the current time).
  DateTime? get _paidAt {
    if (_isToday) return null;
    final noon = DateTime(_day.year, _day.month, _day.day, 12);
    return noon.isBefore(loan.date) ? loan.date : noon;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final symbol = ref.watch(currencyProvider).symbol;
    String money(int c) => Money.format(c, symbol: symbol);
    final cash = ref.watch(cashBalanceProvider).asDataOrNull;
    final wallets = (ref.watch(cardsProvider).asDataOrNull ?? const <PaymentCard>[])
        .where((c) => c.type == CardType.ewallet && !c.archived)
        .toList();
    final selected = _accountId == null ? null : wallets.where((c) => c.id == _accountId).firstOrNull;
    final accountName = selected?.nickname ?? 'Cash';
    final balance = selected?.balance ?? cash;

    final lent = loan.isExpense;
    final cancels = lent && Dates.monthKey(_day) == Dates.monthKey(loan.date);
    final budgetMonth = lent ? loan.date : _day;
    final spent = ref.watch(monthSummaryProvider(Dates.monthKey(budgetMonth))).asDataOrNull?.overall.spent;
    final monthName = DateFormat('MMMM').format(budgetMonth);
    final reduced = Cascade.reduced(context);

    Widget option({required IconData icon, required String title, required String subtitle, required int? id}) {
      final on = _accountId == id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? t.accent.withValues(alpha: 0.10) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: on ? t.accent : t.outline, width: on ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _accountId = id),
            child: Semantics(
              selected: on,
              inMutuallyExclusiveGroup: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      ExcludeSemantics(child: Icon(icon, color: on ? t.accentOnSecond : t.onSecondMuted)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(color: t.onSecond, fontWeight: FontWeight.w700)),
                            Text(subtitle, style: TextStyle(color: t.onSecondMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      ExcludeSemantics(
                        child: Icon(
                          on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                          color: on ? t.accentOnSecond : t.onSecondMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget fromTo(String from, String to) => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(from, style: TextStyle(color: t.onSecondMuted)),
            ExcludeSemantics(child: Icon(Icons.arrow_forward_rounded, size: 16, color: t.onSecondMuted)),
            Text(to, style: TextStyle(color: t.onSecond, fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        );

    // The live preview: what this choice does to the balance and budget.
    final previewKey = '$_accountId|${Dates.dayKey(_day)}|$balance|$spent';
    final preview = Container(
      key: ValueKey(previewKey),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.secondHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Balance · $accountName', style: TextStyle(color: t.onSecondMuted, fontSize: 12)),
          const SizedBox(height: 2),
          if (balance != null)
            fromTo(money(balance), money(lent ? balance + loan.amount : balance - loan.amount))
          else
            Text('…', style: TextStyle(color: t.onSecondMuted)),
          Divider(height: 20, color: t.outline),
          if (cancels || !lent) ...[
            Text('$monthName budget', style: TextStyle(color: t.onSecondMuted, fontSize: 12)),
            const SizedBox(height: 2),
            if (spent != null)
              fromTo('${money(spent)} spent', '${money(cancels ? spent - loan.amount : spent + loan.amount)} spent')
            else
              Text('…', style: TextStyle(color: t.onSecondMuted)),
            if (cancels) ...[
              const SizedBox(height: 8),
              StatusBadge(label: '-${money(loan.amount)} · cancelled', tone: BadgeTone.ok, icon: Icons.check_rounded),
            ],
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(Icons.info_outline_rounded, size: 18, color: t.onSecondMuted)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('This loan stays counted in $monthName\'s budget.', style: TextStyle(color: t.onSecond)),
                ),
              ],
            ),
        ],
      ),
    );

    final dayLabel = _isToday
        ? 'Today (${DateFormat('MMM d').format(_day)})'
        : DateFormat('EEE, MMM d').format(_day);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                lent ? 'How was it paid back to you?' : 'How did you pay it back?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${loan.description} · ${money(loan.amount)} · ${lent ? 'lent' : 'borrowed'} ${DateFormat('MMM d').format(loan.date)}',
                style: TextStyle(color: t.onSecondMuted),
              ),
              const SizedBox(height: 16),
              option(
                icon: accountIcon(null),
                title: 'Cash',
                subtitle: cash == null ? '…' : money(cash),
                id: null,
              ),
              if (wallets.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text('Add an e-wallet (e.g. GCash, Maya) in Wallets to use it here.',
                      style: TextStyle(color: t.onSecondMuted, fontSize: 12)),
                )
              else
                for (final c in wallets)
                  option(
                    icon: accountIcon(c),
                    title: c.nickname,
                    subtitle: '${c.balanceLabel}: ${money(c.balance)}',
                    id: c.id,
                  ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _pickDay,
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text('Paid on: $dayLabel'),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: AnimatedSwitcher(
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 200),
                  child: preview,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop<_PayChoice>(context, (
                  method: _accountId == null ? LoanPayMethod.cash : LoanPayMethod.ewallet,
                  accountId: _accountId,
                  accountName: accountName,
                  paidAt: _paidAt,
                )),
                child: Text(lent ? 'Confirm repayment' : 'Confirm payment'),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
