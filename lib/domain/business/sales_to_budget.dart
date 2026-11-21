import '../../data/models/business.dart';
import '../../data/models/transaction_entry.dart';

/// "Add to Budget": paid sales become personal income, each sale once.
///
/// A sale qualifies only when it is fully paid and has not been added
/// before (its `budget_tx_id` is empty). Unpaid and partly paid orders are
/// left out until the buyer has paid in full.
class SalesToBudget {
  SalesToBudget._();

  static List<BusinessOrder> eligible(Iterable<BusinessOrder> orders) =>
      [for (final o in orders) if (o.isFullyPaid && !o.addedToBudget && !o.isCancelled) o];

  /// The income amount: each order's total (a paid order's money received,
  /// change excluded).
  static int amountOf(Iterable<BusinessOrder> orders) => orders.fold(0, (a, o) => a + o.total);

  static TransactionEntry incomeFor(
    List<BusinessOrder> orders, {
    required int salesCategoryId,
    required int? accountId,
    required DateTime now,
  }) {
    if (orders.isEmpty) throw ArgumentError('No sales to add');
    final ids = [for (final o in orders) '#${o.id}'];
    return TransactionEntry(
      amount: amountOf(orders),
      kind: TransactionKind.income,
      description: orders.length == 1 ? 'Business sale: ${orders.first.buyer}' : 'Business sales (${orders.length} orders)',
      categoryId: salesCategoryId,
      cardId: accountId,
      date: now,
      notes: 'Orders ${ids.join(', ')}',
      source: TransactionSourceType.manual,
      affectsBalance: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}
