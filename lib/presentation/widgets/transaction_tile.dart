import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/category.dart';
import '../../data/models/payment_card.dart';
import '../../data/models/transaction_entry.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// One transaction (Figma "Activity · loan rows"):
///
///     (icon)  Jollibee lunch                -₱250.00
///             Paid with GCash · Food
///             [🔗 Repayment of a loan you gave · Nov 3]   (loan repayments)
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.tx,
    required this.category,
    required this.card,
    this.toCard,
    this.onTap,
    this.showDate = true,
    this.linkedLoan,
  });

  final TransactionEntry tx;
  final Category? category;
  final PaymentCard? card;

  /// Transfers only: the destination account (null = cash).
  final PaymentCard? toCard;
  final VoidCallback? onTap;
  final bool showDate;

  /// Loan repayments: the loan this payment belongs to (for the link chip).
  final TransactionEntry? linkedLoan;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    // E-wallet numbers are masked by PaymentCard.shortLabel.
    String account(int? id, PaymentCard? c) => id == null ? 'Cash' : (c?.shortLabel ?? 'Card');
    final categoryName =
        (tx.customCategory?.trim().isNotEmpty ?? false) ? tx.customCategory!.trim() : (category?.name ?? 'Uncategorized');
    final parts = [
      if (showDate) DateFormat('MMM d').format(tx.date),
      if (tx.isTransfer) ...[
        tx.toCapital ? 'To business' : (tx.fromCapital ? 'From business' : 'Transfer'),
        '${tx.fromCapital ? 'Business capital' : account(tx.cardId, card)} → '
            '${tx.toCapital ? 'Business capital' : account(tx.toCardId, toCard)}',
      ] else if (tx.isSavings) ...[
        tx.isSavingsWithdrawal ? 'Withdrawn from savings' : 'Deposited to savings',
        account(tx.cardId, card),
      ] else ...[
        '${tx.isIncome ? 'Received in' : 'Paid with'} ${account(tx.cardId, card)}',
        categoryName,
        if (tx.isLoanPaid) 'Paid ${DateFormat('MMM d').format(tx.loanPaidAt!)}',
      ],
    ];

    final Widget leading;
    if (tx.isTransfer) {
      leading = const IconBubble(icon: Icons.swap_horiz_rounded);
    } else if (tx.isSavings) {
      leading = IconBubble(icon: Icons.savings_rounded, background: t.successContainer, foreground: t.onSuccessContainer);
    } else if (tx.isLoanPayment) {
      // Money coming back is green; paying back a loan you received is neutral.
      leading = tx.isIncome
          ? IconBubble(icon: Icons.arrow_downward_rounded, background: t.successContainer, foreground: t.onSuccessContainer)
          : const IconBubble(icon: Icons.arrow_upward_rounded);
    } else {
      leading = CategoryAvatar(category: category);
    }

    final loanDate = linkedLoan == null ? '' : ' · ${DateFormat('MMM d').format(linkedLoan!.date)}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 14, Space.lg, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontSize: 16, color: t.onSecond),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.onSecondMuted, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  if (tx.isLoanPayment) ...[
                    const SizedBox(height: Space.sm),
                    _LinkChip(
                      label: '${tx.isIncome ? 'Repayment of a loan you gave' : 'Payment of a loan you received'}$loanDate',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            AmountText(
              tx.amount,
              kind: tx.kind,
              colored: true,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: tx.isIncome ? null : t.onSecond),
            ),
          ],
        ),
      ),
    );
  }
}

/// "🔗 Repayment of a loan you gave · Nov 3".
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2, vertical: Space.xxs),
      decoration: BoxDecoration(color: t.neutralContainer, borderRadius: BorderRadius.circular(Radii.chip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(Icons.link_rounded, size: 15, color: t.onNeutralContainer)),
          const SizedBox(width: Space.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.onNeutralContainer, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
