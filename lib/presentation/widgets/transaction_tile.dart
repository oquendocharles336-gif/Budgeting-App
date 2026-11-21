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
    this.onTap,
    this.showDate = true,
  });

  final TransactionEntry tx;
  final Category? category;
  final PaymentCard? card;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paidWith = tx.isCash ? 'Cash' : (card == null ? 'Card' : '${card!.nickname} ••${card!.last4}');
    final parts = [
      if (showDate) DateFormat('MMM d').format(tx.date),
      category?.name ?? 'Uncategorized',
      paidWith,
    ];
    return ListTile(
      onTap: onTap,
      leading: CategoryAvatar(category: category),
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
