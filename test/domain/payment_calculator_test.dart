import 'package:budgeting_app/domain/business/payment_calculator.dart';
import 'package:budgeting_app/presentation/screens/business/collect_payment_sheet.dart';
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
      expect(r.isExact, isFalse);
      expect(r.isOver, isTrue);
      expect(r.settles, isTrue);
    });

    test('exact amount: no change', () {
      final r = PaymentCalculator.compute(total: 12000, tendered: 12000);
      expect(r.change, 0);
      expect(r.isExact, isTrue);
      expect(r.isOver, isFalse);
      expect(r.settles, isTrue);
    });

    test('less than the total is short and becomes a partial payment', () {
      final r = PaymentCalculator.compute(total: 12000, tendered: 10000);
      expect(r.isShort, isTrue);
      expect(r.isExact, isFalse);
      expect(r.isOver, isFalse);
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
      expect(r.isOver, isTrue);
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

  group('getQuickAmountChips', () {
    test('returns exact amount and higher bill denominations for 120 pesos (12000 centavos)', () {
      final chips = getQuickAmountChips(12000);
      expect(chips, [12000, 20000, 50000, 100000]);
    });

    test('returns exact amount and higher bill denominations for 45 pesos (4500 centavos)', () {
      final chips = getQuickAmountChips(4500);
      expect(chips, [4500, 5000, 10000, 20000, 50000, 100000]);
    });

    test('returns exact amount and higher bill denominations for 350 pesos (35000 centavos)', () {
      final chips = getQuickAmountChips(35000);
      expect(chips, [35000, 50000, 100000]);
    });

    test('returns exact amount and next bill increments for large amounts above 1000 pesos', () {
      final chips = getQuickAmountChips(150000); // 1,500 pesos
      expect(chips.first, 150000);
      expect(chips, contains(200000)); // 2,000 pesos
    });

    test('returns empty list for 0 or negative due', () {
      expect(getQuickAmountChips(0), isEmpty);
      expect(getQuickAmountChips(-100), isEmpty);
    });
  });
}
