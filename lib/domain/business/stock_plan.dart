import '../../data/models/business.dart';

/// An ingredient an order needs more of than is in stock.
class StockShortage {
  const StockShortage({required this.itemId, required this.needed, required this.available});
  final int itemId;
  final double needed;
  final double available;
  double get missing => needed - available;
}

/// Pure stock logic for orders (unit tested). Recipes say how much of each
/// ingredient one unit of a product uses; an order uses that times its
/// quantity. Stock = the sum of the item's ledger rows.
///
/// The ledger rows an order already has ("held") are compared with what it
/// should use now, so running the same step twice adds nothing, and an
/// edit, cancel or delete adds reversing rows instead of rewriting history.
class StockPlan {
  StockPlan._();

  /// Smallest difference that counts (quantities are decimals).
  static const eps = 1e-6;

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  /// Ingredient use of [items]: item id -> amount. Products without a
  /// recipe (and lines whose product was deleted) use nothing.
  static Map<int, double> needed(List<OrderItem> items, Map<int, List<RecipeLine>> recipes) {
    final out = <int, double>{};
    for (final line in items) {
      final pid = line.productId;
      if (pid == null) continue;
      for (final r in recipes[pid] ?? const <RecipeLine>[]) {
        out[r.itemId] = _round((out[r.itemId] ?? 0) + r.quantity * line.quantity);
      }
    }
    return out;
  }

  /// What the order would use beyond what's available. [stock] is the
  /// current ledger stock; [held] is what this order already took (so an
  /// edit can reuse it).
  static List<StockShortage> shortages(
    Map<int, double> needed, {
    required Map<int, double> stock,
    Map<int, double> held = const {},
  }) {
    final out = <StockShortage>[];
    for (final e in needed.entries) {
      final available = _available(e.key, stock, held);
      if (e.value - available > eps) {
        out.add(StockShortage(itemId: e.key, needed: e.value, available: available));
      }
    }
    return out;
  }

  static double _available(int itemId, Map<int, double> stock, Map<int, double> held) {
    final a = (stock[itemId] ?? 0) + (held[itemId] ?? 0);
    return a < 0 ? 0 : a;
  }

  /// Ledger rows that make the order use [needed] (empty map = give
  /// everything back: cancel / delete).
  ///
  /// [currentNet]: the sum of the order's existing rows per item (zero or
  /// negative). Use is capped at what's available, so stock never goes
  /// below zero ("Add anyway" uses what's left).
  static List<StockMovement> movementsFor({
    required int orderId,
    required Map<int, double> needed,
    required Map<int, double> currentNet,
    required Map<int, double> stock,
    required DateTime date,
    required DateTime now,
    String? note,
  }) {
    final held = {for (final e in currentNet.entries) e.key: e.value < 0 ? -e.value : 0.0};
    final out = <StockMovement>[];
    for (final itemId in {...needed.keys, ...held.keys}) {
      final h = held[itemId] ?? 0;
      final want = needed[itemId] ?? 0;
      final available = _available(itemId, stock, held);
      final use = _round(want < available ? want : available);
      if ((use - h).abs() <= eps) continue;
      if (h > eps) {
        out.add(StockMovement(
          itemId: itemId,
          change: _round(h),
          reason: StockReason.orderCancelled,
          orderId: orderId,
          note: note ?? (needed.isEmpty ? 'Order cancelled' : 'Order edited'),
          date: date,
          createdAt: now,
        ));
      }
      if (use > eps) {
        out.add(StockMovement(
          itemId: itemId,
          change: -use,
          reason: StockReason.order,
          orderId: orderId,
          note: note,
          date: date,
          createdAt: now,
        ));
      }
    }
    return out;
  }

  /// The adjustment row that sets an item's stock to [target] (an edit of
  /// the quantity field). Null when nothing changes.
  static StockMovement? adjustTo({
    required int itemId,
    required double current,
    required double target,
    required DateTime now,
    String note = 'Adjusted by hand',
  }) {
    if (target < 0) throw ArgumentError('Stock can\'t be negative');
    final delta = _round(target - current);
    if (delta.abs() <= eps) return null;
    return StockMovement(itemId: itemId, change: delta, reason: StockReason.adjustment, note: note, date: now, createdAt: now);
  }

  /// Stock from ledger rows.
  static double stockOf(Iterable<StockMovement> rows) => _round(rows.fold(0.0, (a, r) => a + r.change));
}
