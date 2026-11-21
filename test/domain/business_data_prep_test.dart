import 'package:budgeting_app/data/models/business.dart';
import 'package:budgeting_app/domain/business/sales_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 20, 14).millisecondsSinceEpoch;

  Map<String, Object?> order(int id, {Object? total = 12000, Object? date, String? buyer = 'Ana', String method = 'cash'}) => {
        'id': id,
        'buyer': buyer,
        'order_date': date ?? day,
        'total': total,
        'paid_amount': total,
        'method': method,
        'status': 'complete',
        'created_at': day,
        'updated_at': day,
      };

  Map<String, Object?> item(int orderId, String? name, int qty, int price) =>
      {'order_id': orderId, 'name': name, 'quantity': qty, 'unit_price': price};

  test('skips orders with no amount or date, never crashes', () {
    final p = BusinessDataPrep.clean(
      [order(1), order(2, total: null), order(3, date: 'not a date'), order(4, total: 0)],
      [item(1, 'Ube jam', 1, 12000)],
    );
    expect(p.orders.map((o) => o.id), [1]);
    expect(p.report.checked, 4);
    expect(p.report.droppedMissingAmount, 2);
    expect(p.report.droppedMissingDate, 1);
    expect(p.report.summaryOf('order'), 'Checked 4 orders · skipped 3 with no amount or date');
  });

  test('a missing total is computed from the items', () {
    final p = BusinessDataPrep.clean([order(1, total: null)], [item(1, 'Cookies', 3, 5000)]);
    expect(p.orders.single.total, 15000);
  });

  test('normalizes text; unnamed items are "Uncategorized"', () {
    final p = BusinessDataPrep.clean([order(1, buyer: '  Ana   Cruz ')], [item(1, '  ', 1, 12000)]);
    expect(p.orders.single.buyer, 'Ana Cruz');
    expect(p.orders.single.items.single.name, 'Uncategorized');
    expect(p.report.uncategorized, 1);
  });

  test('hand-typed repeats are kept by default, removable on request', () {
    final rows = [order(1), order(2)];
    final items = [item(1, 'Ube jam', 1, 12000), item(2, 'Ube jam', 1, 12000)];
    expect(BusinessDataPrep.clean(rows, items).orders, hasLength(2));
    final strict = BusinessDataPrep.clean(rows, items, keepManualRepeats: false);
    expect(strict.orders.map((o) => o.id), [1]);
    expect(strict.report.duplicatesRemoved, 1);
  });

  test('best sellers, payment methods and day buckets', () {
    final p = BusinessDataPrep.clean(
      [order(1, total: 30000), order(2, total: 5000, method: 'maya')],
      [item(1, 'Ube jam', 2, 10000), item(1, 'Cookies', 2, 5000), item(2, 'Cookies', 1, 5000)],
    );
    final s = SalesAnalytics.summarize(p.orders);
    expect(s.bestSellers.first.name, 'Cookies');
    expect(s.bestSellers.first.quantity, 3);
    expect(s.byMethod.first.method, PaymentMethod.cash);
    expect(s.byMethod.last.method, PaymentMethod.maya);
    final days = SalesAnalytics.buckets(p.orders, SalesPeriod.day, DateTime(2026, 11, 21, 9));
    expect(days, hasLength(14));
    expect(days[12].total, 35000); // Nov 20
    expect(days.last.total, 0); // today
  });
}
