import 'package:budgeting_app/data/models/business.dart';
import 'package:budgeting_app/data/repositories/business_repositories.dart';
import 'package:budgeting_app/data/repositories/category_repository.dart';
import 'package:budgeting_app/domain/business/stock_plan.dart';
import 'package:budgeting_app/domain/services/business_service.dart';
import 'package:budgeting_app/domain/services/photo_service.dart';
import 'package:budgeting_app/domain/services/transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';

const sugar = 1;
const eggs = 2;
const cake = 10; // product
const water = 11; // product without a recipe

final recipes = {
  cake: const [RecipeLine(itemId: sugar, quantity: 50), RecipeLine(itemId: eggs, quantity: 2)],
};

/// In-memory orders + stock ledger with the same rules as the SQLite
/// repository: each op key writes once, the planner sees the order's
/// existing ledger rows, and a throw from it saves nothing.
class FakeOrders implements OrderRepository {
  final orders = <int, BusinessOrder>{};
  final ledger = <StockMovement>[];
  final ops = <String, int>{};
  var _next = 1;

  double stock(int item) => ledger.where((m) => m.itemId == item).fold(0.0, (a, m) => a + m.change);

  OrderStockContext _ctx(int orderId, List<OrderItem> items, {required bool cancelled}) {
    final net = <int, double>{};
    for (final m in ledger.where((m) => m.orderId == orderId)) {
      net[m.itemId] = (net[m.itemId] ?? 0) + m.change;
    }
    return OrderStockContext(
      orderId: orderId,
      items: items,
      recipes: recipes,
      currentNet: net,
      stock: {sugar: stock(sugar), eggs: stock(eggs)},
      cancelled: cancelled,
    );
  }

  @override
  Future<BusinessOrder?> byId(int id) async => orders[id];

  @override
  Future<OrderStockContext> stockContext(List<OrderItem> items, {int? orderId}) async =>
      _ctx(orderId ?? -1, items, cancelled: false);

  @override
  Future<int> save(BusinessOrder o, {required StockPlanner planStock, String? opKey}) async {
    if (opKey != null && ops.containsKey(opKey)) return ops[opKey]!;
    final id = o.id ?? _next++;
    final rows = planStock(_ctx(id, o.items, cancelled: orders[id]?.isCancelled ?? false)); // may throw: nothing saved
    orders[id] = BusinessOrder.fromMap({...o.toMap(), 'id': id}, o.items);
    ledger.addAll(rows);
    if (opKey != null) ops[opKey] = id;
    return id;
  }

  @override
  Future<void> saveHeader(BusinessOrder o, {String? opKey}) async => orders[o.id!] = o;

  @override
  Future<void> setStatus(int id, OrderStatus status) async => orders[id] = orders[id]!.copyWith(status: status);

  @override
  Future<void> cancel(int id, {required StockPlanner planStock, String? opKey}) async {
    if (opKey != null && ops.containsKey(opKey)) return;
    final o = orders[id]!;
    ledger.addAll(planStock(_ctx(id, o.items, cancelled: true)));
    orders[id] = BusinessOrder.fromMap({...o.toMap(), 'cancelled_at': 1}, o.items);
    if (opKey != null) ops[opKey] = id;
  }

  @override
  Future<void> delete(int id, {required StockPlanner planStock}) async {
    final o = orders.remove(id)!;
    ledger.addAll(planStock(_ctx(id, o.items, cancelled: true)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Unused implements CapitalRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedProducts implements ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedTransactions implements TransactionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedCategories implements CategoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedPhotos implements PhotoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 11, 21, 10);
  late FakeOrders repo;
  late BusinessService service;

  StockMovement restock(int item, double qty) =>
      StockMovement(itemId: item, change: qty, reason: StockReason.restock, date: now, createdAt: now);

  BusinessOrder order({int? id, int cakes = 2, int waters = 0, OrderStatus status = OrderStatus.deliveredNotPaid}) => BusinessOrder(
        id: id,
        buyer: 'Ana',
        orderDate: now,
        items: [
          if (cakes > 0) OrderItem(productId: cake, name: 'Cake', unitPrice: 50000, quantity: cakes),
          if (waters > 0) OrderItem(productId: water, name: 'Water', unitPrice: 2000, quantity: waters),
        ],
        total: 0,
        status: status,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    repo = FakeOrders()..ledger.addAll([restock(sugar, 1000), restock(eggs, 12)]);
    service = BusinessService(
      capital: Unused(),
      inventory: UnusedInventory(),
      products: UnusedProducts(),
      orders: repo,
      transactions: UnusedTransactions(),
      categories: UnusedCategories(),
      photos: UnusedPhotos(),
      clock: () => now,
    );
  });

  group('deduction', () {
    test('creating an order uses recipe x quantity, before any payment', () async {
      await service.saveOrder(order(cakes: 3));
      expect(repo.stock(sugar), 850); // 1000 - 3 x 50 g
      expect(repo.stock(eggs), 6); // 12 - 3 x 2
    });

    test('products without a recipe don\'t touch stock', () async {
      await service.saveOrder(order(cakes: 0, waters: 5));
      expect(repo.stock(sugar), 1000);
      expect(repo.stock(eggs), 12);
    });

    test('pure plan: needed amounts', () {
      final needed = StockPlan.needed([const OrderItem(productId: cake, name: 'Cake', unitPrice: 1, quantity: 4)], recipes);
      expect(needed, {sugar: 200.0, eggs: 8.0});
    });
  });

  group('no double deduction', () {
    test('retrying the same save (same key) deducts once', () async {
      final a = await service.saveOrder(order(), opKey: 'k1');
      final b = await service.saveOrder(order(), opKey: 'k1');
      expect(b, a);
      expect(repo.orders, hasLength(1));
      expect(repo.stock(eggs), 8);
    });

    test('status changes and payments never change stock again', () async {
      final id = await service.saveOrder(order());
      final before = repo.ledger.length;
      await service.setStatus(id, OrderStatus.delivered);
      await service.saveOrder(repo.orders[id]!.copyWith(paidAmount: 100000, status: OrderStatus.complete));
      expect(repo.ledger.length, before);
      expect(repo.stock(eggs), 8);
    });

    test('planning the same order twice adds nothing the second time', () {
      final first = StockPlan.movementsFor(
        orderId: 5,
        needed: {sugar: 100},
        currentNet: const {},
        stock: {sugar: 1000},
        date: now,
        now: now,
      );
      final net = {sugar: first.fold<double>(0, (a, m) => a + m.change)};
      final again = StockPlan.movementsFor(
        orderId: 5,
        needed: {sugar: 100},
        currentNet: net,
        stock: {sugar: 900},
        date: now,
        now: now,
      );
      expect(again, isEmpty);
    });
  });

  group('reversal', () {
    test('cancel returns the stock with "order_cancelled" rows', () async {
      final id = await service.saveOrder(order(cakes: 2));
      await service.cancelOrder(id);
      expect(repo.stock(sugar), 1000);
      expect(repo.stock(eggs), 12);
      expect(repo.ledger.where((m) => m.reason == StockReason.orderCancelled), hasLength(2));
    });

    test('cancelling twice returns stock once', () async {
      final id = await service.saveOrder(order(cakes: 2));
      await service.cancelOrder(id);
      await service.cancelOrder(id);
      expect(repo.stock(eggs), 12);
    });

    test('delete returns the stock', () async {
      final id = await service.saveOrder(order(cakes: 1));
      await service.deleteOrder(id);
      expect(repo.stock(sugar), 1000);
    });

    test('editing the quantity reverses the old use and applies the new one', () async {
      final id = await service.saveOrder(order(cakes: 2));
      await service.saveOrder(order(id: id, cakes: 5));
      expect(repo.stock(sugar), 750);
      expect(repo.stock(eggs), 2);
      final rows = repo.ledger.where((m) => m.orderId == id).toList();
      // 2 deductions, then 2 reversals + 2 new deductions: history is kept.
      expect(rows, hasLength(6));
    });
  });

  group('never negative', () {
    test('not enough stock: nothing saved unless "Add anyway"', () async {
      await expectLater(service.saveOrder(order(cakes: 10)), throwsA(isA<ShortStockException>()));
      expect(repo.orders, isEmpty);
      expect(repo.stock(eggs), 12);
    });

    test('the warning lists what is missing', () async {
      final short = await service.checkStock(order(cakes: 10).items);
      expect(short.map((s) => s.itemId), [eggs]);
      expect(short.single.needed, 20);
      expect(short.single.available, 12);
    });

    test('"Add anyway" uses what is left and stops at zero', () async {
      await service.saveOrder(order(cakes: 10), allowShortStock: true);
      expect(repo.stock(eggs), 0);
      expect(repo.stock(sugar), 500);
    });

    test('cancelling an "Add anyway" order returns exactly what it took', () async {
      final id = await service.saveOrder(order(cakes: 10), allowShortStock: true);
      await service.cancelOrder(id);
      expect(repo.stock(eggs), 12);
      expect(repo.stock(sugar), 1000);
    });

    test('a hand adjustment can\'t go below zero', () {
      expect(() => StockPlan.adjustTo(itemId: sugar, current: 10, target: -1, now: now), throwsArgumentError);
      expect(StockPlan.adjustTo(itemId: sugar, current: 10, target: 10, now: now), isNull);
      expect(StockPlan.adjustTo(itemId: sugar, current: 10, target: 4, now: now)!.change, -6);
    });
  });
}
