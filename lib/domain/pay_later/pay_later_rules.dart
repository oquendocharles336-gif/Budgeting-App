import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../data/models/pay_later.dart';
import '../../data/models/transaction_entry.dart';

/// Pure Pay Later logic (unit tested).
class PayLaterRules {
  PayLaterRules._();

  /// "Due in 5 days" / "Due tomorrow" / "Due today" / "Overdue by 2 days".
  static String dueLabel(DateTime due, DateTime now) {
    final days = Dates.startOfDay(due).difference(Dates.startOfDay(now)).inDays;
    return switch (days) {
      < 0 => 'Overdue by ${-days} day${days == -1 ? '' : 's'}',
      0 => 'Due today',
      1 => 'Due tomorrow',
      _ => 'Due in $days days',
    };
  }

  static int totalUnpaid(Iterable<PayLaterItem> items) =>
      items.where((i) => !i.isPaid).fold(0, (a, i) => a + i.amount);

  /// The one expense "Paid" creates: the item's amount and category, paid
  /// from [accountId] (null = Cash) on [paidAt]. It moves that account's
  /// balance, like any expense typed by hand.
  static TransactionEntry expenseFor(
    PayLaterItem item, {
    required int? accountId,
    required DateTime paidAt,
    required int fallbackCategoryId,
    required DateTime now,
  }) =>
      TransactionEntry(
        amount: item.amount,
        kind: TransactionKind.expense,
        description: item.item.trim(),
        categoryId: item.categoryId ?? fallbackCategoryId,
        cardId: accountId,
        date: paidAt,
        notes: 'Pay Later, bought ${DateFormat('MMM d, yyyy').format(item.purchaseDate)}',
        source: TransactionSourceType.manual,
        affectsBalance: true,
        createdAt: now,
        updatedAt: now,
      );

  static ({String title, String body}) reminderText({
    required String item,
    required String amountText,
    required DateTime due,
    required DateTime at,
  }) {
    final days = Dates.startOfDay(due).difference(Dates.startOfDay(at)).inDays;
    final when = switch (days) {
      <= 0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };
    return (
      title: 'Pay Later due $when: $item',
      body: '$amountText due on ${DateFormat('MMM d').format(due)}',
    );
  }
}
