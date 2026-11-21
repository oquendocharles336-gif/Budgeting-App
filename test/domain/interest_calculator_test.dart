import 'package:budgeting_app/data/models/debt.dart';
import 'package:budgeting_app/domain/debt/interest_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('simple interest', () {
    test('3% a month on 10,000 is 300 a month', () {
      final q = InterestCalculator.quote(principal: 1000000, remaining: 1000000, rateBp: 300)!;
      expect(q.interestThisMonth, 30000);
      expect(q.dueThisMonth, 30000); // no term: just the interest
      expect(q.monthlyPayment, isNull);
    });

    test('stays on the amount borrowed even after paying some', () {
      final q = InterestCalculator.quote(principal: 1000000, remaining: 400000, rateBp: 300)!;
      expect(q.interestThisMonth, 30000);
    });

    test('with a 6-month term: principal / 6 + interest', () {
      final q = InterestCalculator.quote(principal: 1000000, remaining: 1000000, rateBp: 300, termMonths: 6)!;
      expect(q.monthlyPayment, 196667);
      expect(q.totalInterest, 180000);
      expect(q.dueThisMonth, 196667);
    });

    test('yearly rate is divided by 12', () {
      final q = InterestCalculator.quote(
        principal: 1200000,
        remaining: 1200000,
        rateBp: 1200,
        period: InterestPeriod.year,
      )!;
      expect(q.interestThisMonth, 12000);
    });

    test('never asks for more than what is left plus interest', () {
      final q = InterestCalculator.quote(principal: 1000000, remaining: 10000, rateBp: 300, termMonths: 6)!;
      expect(q.dueThisMonth, 40000);
    });
  });

  group('compound interest', () {
    test('interest is on what is still owed', () {
      final full = InterestCalculator.quote(
        principal: 1200000,
        remaining: 1200000,
        rateBp: 100,
        type: InterestType.compound,
      )!;
      final half = InterestCalculator.quote(
        principal: 1200000,
        remaining: 600000,
        rateBp: 100,
        type: InterestType.compound,
      )!;
      expect(full.interestThisMonth, 12000);
      expect(half.interestThisMonth, 6000);
    });

    test('12% a year over 12 months uses the amortized payment', () {
      final q = InterestCalculator.quote(
        principal: 1200000,
        remaining: 1200000,
        rateBp: 1200,
        type: InterestType.compound,
        period: InterestPeriod.year,
        termMonths: 12,
      )!;
      expect(q.monthlyPayment, 106619);
      expect(q.totalInterest, 79423);
    });
  });

  test('zero rate with a term just splits the amount', () {
    final q = InterestCalculator.quote(principal: 100000, remaining: 100000, rateBp: 0, termMonths: 4)!;
    expect(q.interestThisMonth, 0);
    expect(q.monthlyPayment, 25000);
  });

  test('nothing to work out without a rate or a term', () {
    expect(InterestCalculator.quote(principal: 100000, remaining: 100000), isNull);
  });

  test('settled debts have no quote', () {
    final status = DebtStatus(
      debt: Debt(creditor: 'BPI', totalAmount: 100000, initialPaid: 100000, interestRateBp: 300, createdAt: DateTime(2026)),
      paymentsTotal: 0,
    );
    expect(InterestCalculator.forStatus(status), isNull);
  });
}
