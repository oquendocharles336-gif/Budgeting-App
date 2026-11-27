import '../../core/dates.dart';
import '../../data/models/business.dart';
import '../analytics/data_prep.dart';

/// Cleaned orders plus what the cleaning step did.
class PreparedOrders {
  const PreparedOrders(this.orders, this.report);
  final List<BusinessOrder> orders;
  final PrepReport report;
}

/// The existing data-prep step, applied to orders before any sales total
/// or chart. It reuses [DataPrep]'s parsers and the same rules:
///
///  * an order with no usable total (and no items to compute it from) or
///    no date is skipped, never a crash;
///  * amounts, dates and text are normalized (empty buyer = "Unknown buyer");
///  * an item with no name is counted under "Uncategorized";
///  * duplicates (same buyer, day, total and items) are kept by default,
///    because every order is typed by hand ([DataPrep] keeps manual
///    repeats too); pass `keepManualRepeats: false` to drop them.
class BusinessDataPrep {
  BusinessDataPrep._();

  static const unknownBuyer = 'Unknown buyer';

  static PreparedOrders clean(
    Iterable<Map<String, Object?>> rawOrders,
    Iterable<Map<String, Object?>> rawItems, {
    bool keepManualRepeats = true,
  }) {
    final itemsByOrder = <int, List<OrderItem>>{};
    var uncategorized = 0;
    for (final r in rawItems) {
      final orderId = _int(r['order_id']);
      final qty = _int(r['quantity']);
      final price = DataPrep.parseAmount(r['unit_price']);
      if (orderId == null || qty == null || qty <= 0 || price == null || price < 0) continue;
      var name = DataPrep.normalizeText(r['name']?.toString());
      if (name == null) {
        name = DataPrep.uncategorizedLabel;
        uncategorized++;
      }
      itemsByOrder.putIfAbsent(orderId, () => []).add(OrderItem(
            id: _int(r['id']),
            orderId: orderId,
            productId: _int(r['product_id']),
            name: name,
            unitPrice: price,
            quantity: qty,
          ));
    }

    var checked = 0, noAmount = 0, noDate = 0, synthetic = -1;
    final out = <BusinessOrder>[];
    for (final r in rawOrders) {
      checked++;
      final id = _int(r['id']) ?? synthetic--;
      final items = itemsByOrder[id] ?? const <OrderItem>[];
      var total = DataPrep.parseAmount(r['total'])?.abs();
      if (total == null || total == 0) total = BusinessOrder.totalOf(items);
      if (total == 0) {
        noAmount++;
        continue;
      }
      final date = DataPrep.parseDate(r['order_date']);
      if (date == null) {
        noDate++;
        continue;
      }
      final rawPaid = DataPrep.parseAmount(r['paid_amount']) ?? 0;
      final paid = rawPaid < 0 ? 0 : (rawPaid > total ? total : rawPaid);
      final created = DataPrep.parseDate(r['created_at']) ?? date;
      out.add(BusinessOrder(
        id: id,
        buyer: DataPrep.normalizeText(r['buyer']?.toString()) ?? unknownBuyer,
        orderDate: date,
        items: items,
        total: total,
        paidAmount: paid,
        tendered: DataPrep.parseAmount(r['tendered']),
        changeGiven: DataPrep.parseAmount(r['change_given']),
        method: PaymentMethod.fromDb(r['method']?.toString()),
        status: r['status']?.toString() == 'paid' ? OrderStatus.paid : null,
        fulfillment: FulfillmentStatus.fromDb(r['fulfillment']?.toString()),
        notes: DataPrep.normalizeText(r['notes']?.toString()),
        budgetTxId: _int(r['budget_tx_id']),
        addedToBudgetAt: DataPrep.parseDate(r['added_to_budget_at']),
        createdAt: created,
        updatedAt: DataPrep.parseDate(r['updated_at']) ?? created,
      ));
    }

    var removed = 0;
    var kept = out;
    if (!keepManualRepeats) {
      final seen = <String>{};
      kept = [];
      // Oldest first so the earliest saved copy is the one kept.
      for (final o in [...out]..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0))) {
        if (seen.add(duplicateKey(o))) {
          kept.add(o);
        } else {
          removed++;
        }
      }
      kept.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    }
    return PreparedOrders(
      kept,
      PrepReport(
        checked: checked,
        kept: kept.length,
        droppedMissingAmount: noAmount,
        droppedMissingDate: noDate,
        uncategorized: uncategorized,
        duplicatesRemoved: removed,
      ),
    );
  }

  /// Ids and counts (not money): plain integers.
  static int? _int(Object? v) => switch (v) {
        int i => i,
        double d when d.isFinite => d.round(),
        String s => int.tryParse(s.trim()),
        _ => null,
      };

  static String duplicateKey(BusinessOrder o) => [
        o.buyer.toLowerCase(),
        Dates.dayKey(o.orderDate),
        o.total,
        o.itemsSummary.toLowerCase(),
      ].join('|');
}

enum SalesPeriod {
  day('Day'),
  week('Week'),
  month('Month');

  const SalesPeriod(this.label);
  final String label;
}

class ProductSales {
  const ProductSales({required this.name, required this.quantity, required this.revenue});
  final String name;
  final int quantity;
  final int revenue;
}

/// Money actually received with one payment method. Unpaid orders (and
/// the unpaid part of partly paid ones) aren't counted: their method is
/// only what the owner picked, not money that came in.
class MethodSales {
  const MethodSales({required this.method, required this.orders, required this.total});
  final PaymentMethod method;

  /// Orders with something paid by this method.
  final int orders;

  /// Collected, in centavos.
  final int total;
}

class SalesBucket {
  const SalesBucket({required this.start, required this.label, required this.total});
  final DateTime start;
  final String label;
  final int total;
}

class SalesSummary {
  const SalesSummary({
    required this.totalSales,
    required this.collected,
    required this.unpaid,
    required this.orderCount,
    required this.bestSellers,
    required this.byMethod,
    required this.readyForBudget,
    required this.readyForBudgetCount,
    this.paidCount = 0,
    this.partialCount = 0,
    this.unpaidCount = 0,
    this.partialBalance = 0,
    this.deliveredBalance = 0,
  });

  /// Sum of order totals.
  final int totalSales;

  /// Money actually received.
  final int collected;

  /// Still owed by buyers (the remaining balances, not the totals).
  final int unpaid;

  /// Orders paid in full / partly paid / with nothing paid yet.
  final int paidCount;
  final int partialCount;
  final int unpaidCount;

  /// What partly paid orders still owe (part of [unpaid]).
  final int partialBalance;

  /// Owed on orders already delivered or picked up (collect now).
  final int deliveredBalance;
  final int orderCount;
  final List<ProductSales> bestSellers;
  final List<MethodSales> byMethod;

  /// Fully paid sales not yet added to the personal budget.
  final int readyForBudget;
  final int readyForBudgetCount;
}

/// Sales numbers from cleaned orders. Pure, unit tested.
class SalesAnalytics {
  SalesAnalytics._();

  static SalesSummary summarize(List<BusinessOrder> orders, {int topProducts = 5}) {
    final products = <String, ({String name, int qty, int revenue})>{};
    final methods = <PaymentMethod, ({int orders, int total})>{};
    var total = 0, collected = 0, unpaid = 0, ready = 0, readyCount = 0;
    var paidCount = 0, partialCount = 0, unpaidCount = 0, partialBalance = 0, deliveredBalance = 0;
    for (final o in orders) {
      total += o.total;
      final got = o.paidAmount > o.total ? o.total : o.paidAmount;
      collected += got;
      unpaid += o.balanceDue;
      switch (o.status) {
        case OrderStatus.paid:
          paidCount++;
        case OrderStatus.partiallyPaid:
          partialCount++;
          partialBalance += o.balanceDue;
        case OrderStatus.unpaid:
          unpaidCount++;
      }
      if (o.fulfillment == FulfillmentStatus.delivered) deliveredBalance += o.balanceDue;
      if (o.isFullyPaid && !o.addedToBudget) {
        ready += o.total;
        readyCount++;
      }
      if (got > 0) {
        final m = methods[o.method] ?? (orders: 0, total: 0);
        methods[o.method] = (orders: m.orders + 1, total: m.total + got);
      }
      for (final i in o.items) {
        final key = i.name.toLowerCase();
        final p = products[key] ?? (name: i.name, qty: 0, revenue: 0);
        products[key] = (name: p.name, qty: p.qty + i.quantity, revenue: p.revenue + i.lineTotal);
      }
    }
    final best = [
      for (final p in products.values) ProductSales(name: p.name, quantity: p.qty, revenue: p.revenue),
    ]..sort((a, b) {
        final byQty = b.quantity.compareTo(a.quantity);
        return byQty != 0 ? byQty : b.revenue.compareTo(a.revenue);
      });
    final byMethod = [
      for (final e in methods.entries) MethodSales(method: e.key, orders: e.value.orders, total: e.value.total),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return SalesSummary(
      totalSales: total,
      collected: collected,
      unpaid: unpaid,
      orderCount: orders.length,
      bestSellers: best.take(topProducts).toList(),
      byMethod: byMethod,
      readyForBudget: ready,
      readyForBudgetCount: readyCount,
      paidCount: paidCount,
      partialCount: partialCount,
      unpaidCount: unpaidCount,
      partialBalance: partialBalance,
      deliveredBalance: deliveredBalance,
    );
  }

  /// Sales totals per day (last 14), week (last 8, Monday start) or month
  /// (last 6), oldest first, ending with the one containing [now].
  static List<SalesBucket> buckets(List<BusinessOrder> orders, SalesPeriod period, DateTime now) {
    final starts = <DateTime>[];
    switch (period) {
      case SalesPeriod.day:
        final today = Dates.startOfDay(now);
        for (var i = 13; i >= 0; i--) {
          starts.add(DateTime(today.year, today.month, today.day - i));
        }
      case SalesPeriod.week:
        final week = Dates.startOfWeek(now);
        for (var i = 7; i >= 0; i--) {
          starts.add(DateTime(week.year, week.month, week.day - 7 * i));
        }
      case SalesPeriod.month:
        final month = Dates.monthStart(now);
        for (var i = 5; i >= 0; i--) {
          starts.add(DateTime(month.year, month.month - i));
        }
    }
    DateTime next(DateTime s) => switch (period) {
          SalesPeriod.day => DateTime(s.year, s.month, s.day + 1),
          SalesPeriod.week => DateTime(s.year, s.month, s.day + 7),
          SalesPeriod.month => DateTime(s.year, s.month + 1),
        };
    final totals = List<int>.filled(starts.length, 0);
    for (final o in orders) {
      for (var i = 0; i < starts.length; i++) {
        if (!o.orderDate.isBefore(starts[i]) && o.orderDate.isBefore(next(starts[i]))) {
          totals[i] += o.total;
          break;
        }
      }
    }
    String label(DateTime s) => switch (period) {
          SalesPeriod.day => '${s.month}/${s.day}',
          SalesPeriod.week => '${s.month}/${s.day}',
          SalesPeriod.month => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][s.month - 1],
        };
    return [
      for (var i = 0; i < starts.length; i++) SalesBucket(start: starts[i], label: label(starts[i]), total: totals[i]),
    ];
  }
}
