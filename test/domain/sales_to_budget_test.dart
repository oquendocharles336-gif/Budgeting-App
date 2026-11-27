import 'package:budgeting_app/data/models/business.dart';
import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/data/repositories/business_repositories.dart';
import 'package:budgeting_app/data/repositories/category_repository.dart';
import 'package:budgeting_app/domain/business/sales_analytics.dart';
import 'package:budgeting_app/domain/business/sales_to_budget.dart';
import 'package:budgeting_app/domain/services/business_service.dart';
import 'package:budgeting_app/domain/services/photo_service.dart';
import 'package:budgeting_app/domain/services/transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';

const salesCategory = 55;

class UnusedCapital implements CapitalRepository {
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

class FakeTransactions implements TransactionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePhotos implements PhotoService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCategories implements CategoryRepository {
  @override
  Future<int> salesCategoryId() async => salesCategory;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Orders + the income rows "Add to Budget" creates. Like the real
/// repository, it re-checks eligibility and only flags orders that have
/// no budget link yet.
class FakeOrders implements OrderRepository {
  final orders = <int, BusinessOrder>{};
  final incomes = <int, TransactionEntry>{};
  var _nextTx = 900;

  void put(BusinessOrder o) => orders[o.id!] = o;

  @override
  Future<BusinessOrder?> byId(int id) async => orders[id];

  @override
  Future<AddToBudgetResult> addToBudget({
    Set<int>? onlyIds,
    required List<BusinessOrder> Function(List<BusinessOrder> orders) eligible,
    required TransactionEntry Function(List<BusinessOrder> orders) incomeFor,
  }) async {
    var candidates = orders.values.where((o) => o.budgetTxId == null).toList();
    if (onlyIds != null) candidates = candidates.where((o) => onlyIds.contains(o.id)).toList();
    final chosen = eligible(candidates);
    if (chosen.isEmpty) return (transactionId: null, orders: 0, amount: 0);
    final income = incomeFor(chosen);
    final txId = _nextTx++;
    incomes[txId] = income;
    for (final o in chosen) {
      orders[o.id!] = BusinessOrder.fromMap({...o.toMap(), 'budget_tx_id': txId, 'added_to_budget_at': 1}, o.items);
    }
    return (transactionId: txId, orders: chosen.length, amount: income.amount);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 11, 21, 15);

  BusinessOrder order(int id, {required int total, required int paid, String buyer = 'Ana'}) => BusinessOrder(
        id: id,
        buyer: buyer,
        orderDate: now,
        items: [OrderItem(productId: 1, name: 'Ube jam', unitPrice: total, quantity: 1)],
        total: total,
        paidAmount: paid,
        createdAt: now,
        updatedAt: now,
      );

  late FakeOrders repo;
  late BusinessService service;

  setUp(() {
    repo = FakeOrders();
    service = BusinessService(
      capital: UnusedCapital(),
      inventory: UnusedInventory(),
      products: UnusedProducts(),
      orders: repo,
      transactions: FakeTransactions(),
      categories: FakeCategories(),
      photos: FakePhotos(),
      clock: () => now,
    );
  });

  test('only fully paid sales not added before are eligible', () {
    final paid = order(1, total: 12000, paid: 12000);
    final partial = order(2, total: 12000, paid: 5000);
    final unpaid = order(3, total: 12000, paid: 0);
    final added = BusinessOrder.fromMap({...order(4, total: 9000, paid: 9000).toMap(), 'budget_tx_id': 7}, const []);
    expect(SalesToBudget.eligible([paid, partial, unpaid, added]).map((o) => o.id), [1]);
  });

  test('adds paid sales once as income in "Business / sales"', () async {
    repo
      ..put(order(1, total: 12000, paid: 12000))
      ..put(order(2, total: 30000, paid: 30000, buyer: 'Ben'));
    final r = await service.addSalesToBudget(accountId: 4);
    expect(r.orders, 2);
    expect(r.amount, 42000);
    final income = repo.incomes.values.single;
    expect(income.kind, TransactionKind.income);
    expect(income.categoryId, salesCategory);
    expect(income.cardId, 4);
    expect(income.amount, 42000);
    expect(income.affectsBalance, isTrue);
    expect(repo.orders[1]!.addedToBudget, isTrue);
    expect(repo.orders[2]!.addedToBudget, isTrue);
  });

  test('pressing "Add to Budget" again adds nothing', () async {
    repo.put(order(1, total: 12000, paid: 12000));
    await service.addSalesToBudget(accountId: null);
    final again = await service.addSalesToBudget(accountId: null);
    expect(again.orders, 0);
    expect(again.transactionId, isNull);
    expect(repo.incomes, hasLength(1));
  });

  test('unpaid and partly paid sales are never added; added once paid in full', () async {
    repo
      ..put(order(1, total: 12000, paid: 0))
      ..put(order(2, total: 12000, paid: 6000));
    final first = await service.addSalesToBudget(accountId: null);
    expect(first.orders, 0);
    expect(repo.incomes, isEmpty);

    repo.put(order(2, total: 12000, paid: 12000)); // buyer paid the rest
    final second = await service.addSalesToBudget(accountId: null);
    expect(second.orders, 1);
    expect(repo.incomes.values.single.amount, 12000);
    expect(repo.orders[1]!.addedToBudget, isFalse);
  });

  test('sales summary: ready-for-budget excludes added and unpaid sales', () {
    final added = BusinessOrder.fromMap({...order(3, total: 9000, paid: 9000).toMap(), 'budget_tx_id': 7}, const []);
    final s = SalesAnalytics.summarize([order(1, total: 12000, paid: 12000), order(2, total: 5000, paid: 1000), added]);
    expect(s.totalSales, 26000);
    expect(s.collected, 22000);
    expect(s.unpaid, 4000);
    expect(s.readyForBudget, 12000);
    expect(s.readyForBudgetCount, 1);
  });

  test('sales summary: balances, partial counts and money received by method', () {
    final partial = order(2, total: 50000, paid: 20000);
    final delivered = BusinessOrder.fromMap({...order(4, total: 8000, paid: 0).toMap(), 'fulfillment': 'delivered'}, const []);
    final maya = BusinessOrder.fromMap({...order(5, total: 3000, paid: 3000).toMap(), 'method': 'maya'}, const []);
    final s = SalesAnalytics.summarize([order(1, total: 12000, paid: 12000), partial, delivered, maya]);
    expect(s.totalSales, 73000);
    expect(s.collected, 35000);
    // Remaining balances, not order totals: 30,000 + 8,000.
    expect(s.unpaid, 38000);
    expect(s.paidCount, 2);
    expect(s.partialCount, 1);
    expect(s.unpaidCount, 1);
    expect(s.partialBalance, 30000);
    expect(s.deliveredBalance, 8000);
    // Only money received counts per method; the unpaid order adds nothing.
    final cash = s.byMethod.firstWhere((m) => m.method == PaymentMethod.cash);
    expect(cash.total, 32000);
    expect(cash.orders, 2);
    expect(s.byMethod.firstWhere((m) => m.method == PaymentMethod.maya).total, 3000);
  });
}
