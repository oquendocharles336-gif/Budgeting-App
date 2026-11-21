import 'package:budgeting_app/domain/business/payment_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('change calculation (centavos)', () {
    test('500 cash for a 120 total gives 380 change', () {
      final r = PaymentCalculator.compute(total: 12000, tendered: 50000);
      expect(r.due, 12000);
      expect(r.applied, 12000);
      expect(r.change, 38000);
      expect(r.remaining, 0);
      expect(r.isShort, isFalse);
      expect(r.settles, isTrue);
    });

    test('exact amount: no change', () {
      final r = PaymentCalculator.compute(total: 12000, tendered: 12000);
      expect(r.change, 0);
      expect(r.settles, isTrue);
    });

    test('less than the total is short and becomes a partial payment', () {
      final r = PaymentCalculator.compute(total: 12000, tendered: 10000);
      expect(r.isShort, isTrue);
      expect(r.isPartial, isTrue);
      expect(r.applied, 10000);
      expect(r.change, 0);
      expect(r.remaining, 2000);
    });

    test('a second payment only covers what is still owed', () {
      final r = PaymentCalculator.compute(total: 12000, alreadyPaid: 10000, tendered: 5000);
      expect(r.due, 2000);
      expect(r.applied, 2000);
      expect(r.change, 3000);
      expect(r.remaining, 0);
    });

    test('nothing owed: the whole amount is change', () {
      final r = PaymentCalculator.compute(total: 12000, alreadyPaid: 12000, tendered: 1000);
      expect(r.due, 0);
      expect(r.applied, 0);
      expect(r.change, 1000);
      expect(r.settles, isFalse);
    });

    test('nothing handed over yet', () {
      final r = PaymentCalculator.compute(total: 12000, tendered: 0);
      expect(r.applied, 0);
      expect(r.isPartial, isFalse);
      expect(r.remaining, 12000);
    });

    test('negative amounts are rejected', () {
      expect(() => PaymentCalculator.compute(total: 100, tendered: -1), throwsArgumentError);
      expect(() => PaymentCalculator.compute(total: -100, tendered: 1), throwsArgumentError);
    });
  });
}
