import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/category.dart';
import '../../data/models/payment_card.dart';
import '../../data/models/transaction_entry.dart';
import 'common.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.tx,
    required this.category,
    required this.card,
    this.toCard,
    this.onTap,
    this.showDate = true,
  });

  final TransactionEntry tx;
  final Category? category;
  final PaymentCard? card;

  /// Transfers only: the destination account (null = cash).
  final PaymentCard? toCard;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // E-wallet numbers are masked by PaymentCard.shortLabel.
    String account(int? id, PaymentCard? c) => id == null ? 'Cash' : (c?.shortLabel ?? 'Card');
    final parts = [
      if (showDate) DateFormat('MMM d').format(tx.date),
      if (tx.isTransfer) ...[
        tx.toCapital ? 'To business' : (tx.fromCapital ? 'From business' : 'Transfer'),
        '${tx.fromCapital ? 'Business capital' : account(tx.cardId, card)} → '
            '${tx.toCapital ? 'Business capital' : account(tx.toCardId, toCard)}',
      ] else ...[
        // "Other" shows what the user typed, e.g. "Pet food".
        (tx.customCategory?.trim().isNotEmpty ?? false) ? tx.customCategory!.trim() : (category?.name ?? 'Uncategorized'),
        account(tx.cardId, card),
        if (tx.isLoanPaid) 'Paid ${DateFormat('MMM d').format(tx.loanPaidAt!)}',
      ],
    ];
    return ListTile(
      onTap: onTap,
      leading: tx.isTransfer
          ? Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(44 * 0.32),
              ),
              child: Icon(Icons.swap_horiz_rounded, color: scheme.onSecondaryContainer, size: 22),
            )
          : CategoryAvatar(category: category),
      title: Text(tx.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
      trailing: AmountText(
        tx.amount,
        kind: tx.kind,
        colored: true,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}
