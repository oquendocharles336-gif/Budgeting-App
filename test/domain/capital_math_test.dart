import 'package:budgeting_app/data/models/business.dart';
import 'package:budgeting_app/domain/business/capital_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 21);
  CapitalEntry e(int amount, String kind) => CapitalEntry(amount: amount, kind: kind, date: now, createdAt: now);

  test('balance is the sum of the ledger (sales rows change nothing)', () {
    final ledger = [
      e(100000, CapitalKind.deposit),
      e(-30000, CapitalKind.withdrawal),
      e(-1500, CapitalKind.fee),
      CapitalEntry(amount: 0, kind: CapitalKind.salesAdded, memoAmount: 50000, date: now, createdAt: now),
    ];
    expect(CapitalMath.balance(ledger), 68500);
  });

  group('withdrawal limit', () {
    test('up to the balance, fee included', () {
      expect(CapitalMath.withdrawError(balance: 10000, amount: 9000, fee: 1000), isNull);
      expect(CapitalMath.withdrawError(balance: 10000, amount: 9500, fee: 1000), 'More than the capital balance');
      expect(CapitalMath.withdrawError(balance: 0, amount: 1), 'There is no capital to withdraw');
      expect(CapitalMath.withdrawError(balance: 100, amount: 0), isNotNull);
      expect(CapitalMath.withdrawError(balance: 100, amount: 10, fee: -1), isNotNull);
    });

    test('planning over the limit throws', () {
      expect(() => CapitalMath.planWithdraw(balance: 5000, amount: 5000, fee: 1), throwsA(isA<CapitalLimitException>()));
    });
  });

  group('fee math', () {
    test('capital pays amount + fee, the personal account gets the amount', () {
      final p = CapitalMath.planWithdraw(balance: 50000, amount: 20000, fee: 1500);
      expect(p.capitalDebit, 21500);
      expect(p.personalCredit, 20000);
    });

    test('the fee is its own ledger row; the balance drops by amount + fee', () {
      final p = CapitalMath.planWithdraw(balance: 50000, amount: 20000, fee: 1500);
      final rows = CapitalMath.withdrawEntries(p, date: now, now: now, transactionId: 7);
      expect(rows.map((r) => (r.kind, r.amount)), [(CapitalKind.withdrawal, -20000), (CapitalKind.fee, -1500)]);
      expect(rows.every((r) => r.transactionId == 7), isTrue);
      expect(CapitalMath.balance([e(50000, CapitalKind.deposit), ...rows]), 28500);
    });

    test('no fee: one row', () {
      final p = CapitalMath.planWithdraw(balance: 50000, amount: 20000);
      expect(CapitalMath.withdrawEntries(p, date: now, now: now), hasLength(1));
    });
  });
}
