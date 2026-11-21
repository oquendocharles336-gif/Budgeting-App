import '../../data/models/business.dart';
import '../../data/repositories/business_repositories.dart';
import '../../data/repositories/category_repository.dart';
import '../business/capital_math.dart';
import '../business/payment_calculator.dart';
import '../business/sales_to_budget.dart';
import '../business/stock_plan.dart';
import 'photo_service.dart';
import 'transaction_service.dart';

export '../business/capital_math.dart' show CapitalLimitException;
export '../business/stock_plan.dart' show StockShortage;

/// Thrown when a payment is less than what is owed and partial payment
/// wasn't allowed. The UI asks first, then retries with `allowPartial`.
class ShortPaymentException implements Exception {
  const ShortPaymentException(this.result);
  final PaymentResult result;
  @override
  String toString() => 'The amount given is less than the amount due.';
}

/// Thrown when an order needs more ingredients than are in stock and the
/// user didn't choose "Add anyway". Nothing was saved.
class ShortStockException implements Exception {
  const ShortStockException(this.shortages);
  final List<StockShortage> shortages;
  @override
  String toString() => 'Not enough stock';
}

/// The business side: capital, inventory, products, orders and moving paid
/// sales into the personal budget.
///
/// Every write that could be repeated (double tap, "Try again") takes an
/// `opKey`: the same key never writes twice.
class BusinessService {
  BusinessService({
    required this._capital,
    required this._inventory,
    required this._products,
    required this._orders,
    required this._transactions,
    required this._categories,
    required this._photos,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CapitalRepository _capital;
  final InventoryRepository _inventory;
  final ProductRepository _products;
  final OrderRepository _orders;
  final TransactionService _transactions;
  final CategoryRepository _categories;
  final PhotoService _photos;
  final DateTime Function() _clock;

  // ---------------------------------------------------------------------------
  // Capital
  // ---------------------------------------------------------------------------

  /// Moves money from a personal account (null = Cash) into business
  /// capital: a transfer, so the personal balance goes down by amount + fee,
  /// capital goes up by the amount, and the fee is a personal "Fees" expense.
  Future<int> moveToCapital({
    required int amount,
    int fee = 0,
    required int? fromAccountId,
    DateTime? date,
    String? note,
    String? opKey,
  }) =>
      _transactions.createTransfer(
        amount: amount,
        fee: fee,
        fromAccountId: fromAccountId,
        toCapital: true,
        date: date ?? _clock(),
        description: 'Business capital',
        notes: _clean(note),
        opKey: opKey,
      );

  /// Takes money out of capital into a personal account (null = Cash).
  /// Capital goes down by amount + fee; it can't go below zero
  /// ([CapitalLimitException], checked before and inside the save).
  Future<int> withdrawFromCapital({
    required int amount,
    int fee = 0,
    required int? toAccountId,
    DateTime? date,
    String? note,
    String? opKey,
  }) async {
    CapitalMath.planWithdraw(balance: await _capital.balance(), amount: amount, fee: fee);
    return _transactions.withdrawFromCapital(
      amount: amount,
      fee: fee,
      toAccountId: toAccountId,
      date: date ?? _clock(),
      notes: _clean(note),
      opKey: opKey,
    );
  }

  /// Deletes a deposit or withdrawal and the transfer (and fee) that made it.
  Future<void> deleteCapitalEntry(CapitalEntry e) {
    if (e.kind == CapitalKind.salesAdded || e.kind == CapitalKind.fee) {
      throw StateError('Delete the deposit or withdrawal this belongs to instead.');
    }
    return _capital.delete(e);
  }

  static String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  // ---------------------------------------------------------------------------
  // Inventory
  // ---------------------------------------------------------------------------

  /// Saves the item. A new item's quantity becomes its first ledger row; an
  /// edited quantity becomes an "adjustment" row (never below zero). A
  /// replaced photo's old file is deleted afterwards.
  Future<int> saveItem(InventoryItem item, {String? previousPhoto, String? opKey}) async {
    final name = item.name.trim();
    if (name.isEmpty) throw ArgumentError('Enter a name');
    if (item.unit.trim().isEmpty) throw ArgumentError('Choose a unit');
    if (item.quantity < 0) throw ArgumentError('Quantity can\'t be negative');
    if (item.lowStock != null && item.lowStock! < 0) throw ArgumentError('Low-stock level can\'t be negative');
    final now = _clock();
    final clean = item.copyWith(name: name, unit: item.unit.trim(), updatedAt: now);
    final int id;
    if (item.id == null) {
      id = await _inventory.insert(clean, opKey: opKey);
    } else {
      id = item.id!;
      // Recomputed from the ledger inside the save: retrying sets the same
      // target again and adds nothing.
      await _inventory.update(
        clean,
        adjustment: (current) => StockPlan.adjustTo(itemId: id, current: current, target: clean.quantity, now: now),
      );
    }
    if (previousPhoto != null && previousPhoto != item.photoPath) await _photos.delete(previousPhoto);
    return id;
  }

  Future<void> restock(int id, double amount, {String? opKey}) async {
    if (amount <= 0) throw ArgumentError('Enter how much to add');
    await _inventory.restock(id, amount, opKey: opKey);
  }

  Future<List<StockMovement>> stockHistory(int itemId) => _inventory.movements(itemId);

  Future<void> deleteItem(InventoryItem item) async {
    await _inventory.delete(item.id!);
    await _photos.delete(item.photoPath);
  }

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------

  /// Saves the product and its recipe (ingredients per 1 unit). A recipe
  /// change affects future orders only.
  Future<int> saveProduct(Product p, {List<RecipeLine>? recipe, String? previousPhoto, String? opKey}) async {
    final name = p.name.trim();
    if (name.isEmpty) throw ArgumentError('Enter a name');
    if (p.price < 0) throw ArgumentError('Price can\'t be negative');
    if (recipe != null && recipe.any((l) => l.quantity <= 0)) throw ArgumentError('Ingredient amounts must be more than zero');
    final clean = p.copyWith(name: name, updatedAt: _clock());
    final int id;
    if (p.id == null) {
      id = await _products.insert(clean, recipe: recipe ?? const [], opKey: opKey);
    } else {
      await _products.update(clean, recipe: recipe);
      id = p.id!;
    }
    if (previousPhoto != null && previousPhoto != p.photoPath) await _photos.delete(previousPhoto);
    return id;
  }

  Future<List<RecipeLine>> recipe(int productId) => _products.recipe(productId);

  Future<void> deleteProduct(Product p) async {
    await _products.delete(p.id!);
    await _photos.delete(p.photoPath);
  }

  // ---------------------------------------------------------------------------
  // Orders
  // ---------------------------------------------------------------------------

  /// What a new or edited order would be short of (empty = enough stock).
  Future<List<StockShortage>> checkStock(List<OrderItem> items, {int? orderId}) async {
    final ctx = await _orders.stockContext(items, orderId: orderId);
    final needed = StockPlan.needed(items, ctx.recipes);
    return StockPlan.shortages(needed, stock: ctx.stock, held: _held(ctx.currentNet));
  }

  static Map<int, double> _held(Map<int, double> net) => {for (final e in net.entries) e.key: e.value < 0 ? -e.value : 0.0};

  /// The stock step of a save: uses the ingredients when the order is
  /// created (payment doesn't matter), adjusts them on edit, gives them back
  /// for a cancelled order. Without [allowShortStock] a shortage cancels the
  /// whole save; with it, what's left is used (never below zero).
  StockPlanner _planner({required bool allowShortStock, required DateTime date}) => (ctx) {
        final needed = ctx.cancelled ? const <int, double>{} : StockPlan.needed(ctx.items, ctx.recipes);
        if (!allowShortStock && !ctx.cancelled) {
          final short = StockPlan.shortages(needed, stock: ctx.stock, held: _held(ctx.currentNet));
          if (short.isNotEmpty) throw ShortStockException(short);
        }
        return StockPlan.movementsFor(
          orderId: ctx.orderId,
          needed: needed,
          currentNet: ctx.currentNet,
          stock: ctx.stock,
          date: date,
          now: _clock(),
        );
      };

  /// Saves an order. The total is always the sum of the items (no other
  /// charges), and what was paid is capped at the total. Stock is used
  /// only when the items change (or the order is new): saving a payment,
  /// status or note never touches stock. A sale already added to the
  /// budget can't change its total.
  Future<int> saveOrder(BusinessOrder order, {bool allowShortStock = false, String? opKey}) async {
    final buyer = order.buyer.trim();
    if (buyer.isEmpty) throw ArgumentError('Enter the buyer\'s name');
    if (order.items.isEmpty) throw ArgumentError('Add at least one item');
    if (order.items.any((i) => i.quantity <= 0)) throw ArgumentError('Quantities must be more than zero');
    final total = BusinessOrder.totalOf(order.items);
    final paid = order.paidAmount > total ? total : order.paidAmount;
    final clean = order.copyWith(buyer: buyer, total: total, paidAmount: paid, updatedAt: _clock());
    if (order.id != null) {
      final before = await _orders.byId(order.id!);
      if (before != null && before.addedToBudget && before.total != total) {
        throw StateError('This sale is already in your budget, so its items can\'t change.');
      }
      if (before != null && sameItems(before.items, order.items)) {
        await _orders.saveHeader(clean, opKey: opKey);
        return order.id!;
      }
    }
    return _orders.save(clean, planStock: _planner(allowShortStock: allowShortStock, date: clean.orderDate), opKey: opKey);
  }

  /// Same products and quantities (prices and names may be copies).
  static bool sameItems(List<OrderItem> a, List<OrderItem> b) {
    String key(OrderItem i) => '${i.productId}|${i.name}|${i.unitPrice}|${i.quantity}';
    final ka = a.map(key).toList()..sort();
    final kb = b.map(key).toList()..sort();
    if (ka.length != kb.length) return false;
    for (var i = 0; i < ka.length; i++) {
      if (ka[i] != kb[i]) return false;
    }
    return true;
  }

  /// The payment counter. [tendered] is what the buyer handed over. If it
  /// is less than what's due, [ShortPaymentException] is thrown unless
  /// [allowPartial]. Each [opKey] is recorded once (a retry can't pay twice).
  Future<PaymentResult> recordPayment(
    int orderId, {
    required int tendered,
    required PaymentMethod method,
    bool allowPartial = false,
    String? opKey,
  }) async {
    final order = await _orders.byId(orderId);
    if (order == null) throw StateError('This order no longer exists');
    final result = PaymentCalculator.compute(total: order.total, alreadyPaid: order.paidAmount, tendered: tendered);
    if (result.due == 0) return result;
    if (result.applied == 0) throw ArgumentError('Enter the amount received');
    if (result.isShort && !allowPartial) throw ShortPaymentException(result);
    final paid = order.paidAmount + result.applied;
    final fullyPaid = paid >= order.total;
    await _orders.saveHeader(
      order.copyWith(
        paidAmount: paid,
        method: method,
        tendered: () => method.isCash ? tendered : null,
        changeGiven: () => method.isCash ? result.change : null,
        status: fullyPaid ? statusAfterFullPayment(order.status) : order.status,
        updatedAt: _clock(),
      ),
      opKey: opKey,
    );
    return result;
  }

  /// Once paid in full: delivered orders become Complete, others Paid.
  static OrderStatus statusAfterFullPayment(OrderStatus s) => switch (s) {
        OrderStatus.delivered || OrderStatus.deliveredNotPaid || OrderStatus.complete => OrderStatus.complete,
        OrderStatus.paid => OrderStatus.paid,
      };

  /// Changes the status (never stock). "Paid" / "Complete" on an order with
  /// a balance needs [recordFullPayment], so the status and money agree.
  /// Setting the same status twice is harmless, so retries are safe.
  Future<void> setStatus(int orderId, OrderStatus status, {bool recordFullPayment = false, String? opKey}) async {
    final order = await _orders.byId(orderId);
    if (order == null) return;
    if (status.claimsPaid && order.balanceDue > 0) {
      if (!recordFullPayment) throw StateError('The buyer still has a balance to pay');
      await _orders.saveHeader(order.copyWith(paidAmount: order.total, status: status, updatedAt: _clock()), opKey: opKey);
      return;
    }
    await _orders.setStatus(orderId, status);
  }

  /// Cancels the order and returns its ingredients to stock. Not possible
  /// once its sale is in the budget (delete that income first).
  Future<void> cancelOrder(int id, {String? opKey}) async {
    final order = await _orders.byId(id);
    if (order == null || order.isCancelled) return;
    if (order.addedToBudget) {
      throw StateError('This sale is already in your budget. Delete its income in Activity first.');
    }
    await _orders.cancel(id, planStock: _planner(allowShortStock: true, date: _clock()), opKey: opKey);
  }

  /// Deletes the order and returns its ingredients to stock.
  Future<void> deleteOrder(int id) => _orders.delete(id, planStock: _planner(allowShortStock: true, date: _clock()));

  /// Adds every fully paid sale not added before (or only [onlyIds]) to
  /// the personal budget as income into [accountId] (null = Cash). Each
  /// sale is flagged, so it is never added twice; unpaid and cancelled
  /// sales are skipped. Capital is not touched.
  Future<AddToBudgetResult> addSalesToBudget({required int? accountId, Set<int>? onlyIds}) async {
    final categoryId = await _categories.salesCategoryId();
    final now = _clock();
    return _orders.addToBudget(
      onlyIds: onlyIds,
      eligible: SalesToBudget.eligible,
      incomeFor: (orders) => SalesToBudget.incomeFor(orders, salesCategoryId: categoryId, accountId: accountId, now: now),
    );
  }
}
