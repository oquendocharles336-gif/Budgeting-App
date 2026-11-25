import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/domain/analytics/spending_analytics.dart';
import 'package:budgeting_app/domain/budget/budget_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionEntry tx(int amount, {TransactionKind kind = TransactionKind.expense, int? categoryId, DateTime? date}) {
  final d = date ?? DateTime(2026, 11, 10);
  return TransactionEntry(
    id: 1,
    amount: amount,
    kind: kind,
    description: 'x',
    categoryId: categoryId,
    date: d,
    createdAt: d,
    updatedAt: d,
  );
}

void main() {
  final nov = DateTime(2026, 11);
  final nov21 = DateTime(2026, 11, 21, 10);

  group('levels and percent', () {
    test('80% and 100% thresholds', () {
      expect(BudgetCalculator.levelFor(budget: 1000, spent: 799), BudgetLevel.ok);
      expect(BudgetCalculator.levelFor(budget: 1000, spent: 800), BudgetLevel.warning);
      expect(BudgetCalculator.levelFor(budget: 1000, spent: 999), BudgetLevel.warning);
      expect(BudgetCalculator.levelFor(budget: 1000, spent: 1000), BudgetLevel.exceeded);
      expect(BudgetCalculator.levelFor(budget: 1000, spent: 5000), BudgetLevel.exceeded);
      expect(BudgetCalculator.levelFor(budget: 0, spent: 5000), BudgetLevel.none);
    });

    test('percent rounds down so 79.9% is not shown as 80%', () {
      const p = BudgetProgress(budget: 3000, spent: 2399);
      expect(p.percentUsed, 79);
      expect(p.level, BudgetLevel.ok);
    });

    test('remaining goes negative when over budget', () {
      const p = BudgetProgress(budget: 1000, spent: 1250);
      expect(p.remaining, -250);
      expect(p.ratio, 1.25);
    });

    test('no budget', () {
      const p = BudgetProgress(budget: 0, spent: 500);
      expect(p.hasBudget, isFalse);
      expect(p.percentUsed, 0);
    });
  });

  group('alerts', () {
    test('thresholdsReached', () {
      expect(BudgetCalculator.thresholdsReached(budget: 1000, spent: 500), isEmpty);
      expect(BudgetCalculator.thresholdsReached(budget: 1000, spent: 850), [80]);
      expect(BudgetCalculator.thresholdsReached(budget: 1000, spent: 1200), [80, 100]);
      expect(BudgetCalculator.thresholdsReached(budget: 0, spent: 50), isEmpty);
    });

    test('each alert fires once per month', () {
      expect(BudgetCalculator.newAlerts(budget: 1000, spent: 850, alreadySent: {}), [80]);
      expect(BudgetCalculator.newAlerts(budget: 1000, spent: 850, alreadySent: {80}), isEmpty);
      expect(BudgetCalculator.newAlerts(budget: 1000, spent: 1200, alreadySent: {80}), [100]);
    });
  });

  group('spent', () {
    test('counts only expenses', () {
      final txs = [tx(1000), tx(500), tx(9999, kind: TransactionKind.income)];
      expect(BudgetCalculator.spent(txs), 1500);
    });

    test('filters by category', () {
      final txs = [tx(1000, categoryId: 1), tx(500, categoryId: 2), tx(300, categoryId: 1)];
      expect(BudgetCalculator.spent(txs, categoryId: 1), 1300);
      expect(BudgetCalculator.spent(txs, categoryId: 3), 0);
    });
  });

  group('daily figures', () {
    test('days elapsed for current, past and future months', () {
      expect(BudgetCalculator.daysElapsed(nov, nov21), 21);
      expect(BudgetCalculator.daysElapsed(DateTime(2026, 10), nov21), 31);
      expect(BudgetCalculator.daysElapsed(DateTime(2026, 12), nov21), 0);
      expect(BudgetCalculator.daysElapsed(nov, DateTime(2026, 11, 1)), 1);
    });

    test('average daily spend', () {
      expect(BudgetCalculator.averageDaily(spent: 210000, month: nov, now: nov21), 10000);
      expect(BudgetCalculator.averageDaily(spent: 1000, month: DateTime(2026, 12), now: nov21), 0);
    });

    test('safe daily spend counts today as a remaining day', () {
      // 9,000 left, 10 days left (21st..30th) -> 900/day.
      expect(
        BudgetCalculator.safeDailySpend(budget: 3000000, spent: 2100000, month: nov, now: nov21),
        90000,
      );
      expect(BudgetCalculator.safeDailySpend(budget: 1000, spent: 1500, month: nov, now: nov21), 0);
    });

    test('projected month-end spend', () {
      expect(BudgetCalculator.projectedMonthEnd(spent: 2100000, month: nov, now: nov21), 3000000);
    });
  });

  group('SpendingAnalytics', () {
    test('daily totals and categories', () {
      final txs = [
        tx(1000, categoryId: 1, date: DateTime(2026, 11, 1)),
        tx(500, categoryId: 2, date: DateTime(2026, 11, 1)),
        tx(300, categoryId: 1, date: DateTime(2026, 11, 30)),
        tx(9999, kind: TransactionKind.income, date: DateTime(2026, 11, 2)),
      ];
      final daily = SpendingAnalytics.dailyTotals(txs, nov);
      expect(daily.length, 30);
      expect(daily[0], 1500);
      expect(daily[1], 0);
      expect(daily[29], 300);

      final cats = SpendingAnalytics.byCategory(txs);
      expect(cats.first.categoryId, 1);
      expect(cats.first.total, 1300);
      expect(cats.first.count, 2);
    });

    test('weeks of November 2026 (the 1st is a Sunday)', () {
      final weeks = SpendingAnalytics.weeksOfMonth(const [], nov);
      expect(weeks.map((w) => w.label).toList(), ['1', '2–8', '9–15', '16–22', '23–29', '30']);
    });

    test('week over week compares the same number of days', () {
      final txs = [
        tx(100, date: DateTime(2026, 11, 16)), // Mon this week
        tx(200, date: DateTime(2026, 11, 21)), // Sat this week (today)
        tx(400, date: DateTime(2026, 11, 9)), // Mon last week
        tx(800, date: DateTime(2026, 11, 15)), // Sun last week: after the same point, excluded
      ];
      final c = SpendingAnalytics.weekOverWeek(txs, nov21);
      expect(c.current, 300);
      expect(c.previous, 400);
      expect(c.changeRatio, -0.25);
    });
  });

  group('loans repaid in the same month', () {
    TransactionEntry loan(int amount, {required DateTime lent, DateTime? paid, TransactionKind kind = TransactionKind.expense}) =>
        TransactionEntry(
          id: 9,
          amount: amount,
          kind: kind,
          description: 'Ana — groceries',
          categoryId: 7,
          date: lent,
          loanPaidAt: paid,
          createdAt: lent,
          updatedAt: lent,
        );

    final food = tx(185000, categoryId: 1);

    test('a loan you gave and got back the same month is not spending', () {
      final l = loan(100000, lent: DateTime(2026, 11, 3), paid: DateTime(2026, 11, 20));
      expect(l.isLoanCancelledByRepayment, isTrue);
      expect(BudgetCalculator.spent([food, l]), 185000);
      expect(BudgetCalculator.spent([food, l], categoryId: 7), 0);
      expect(BudgetCalculator.loansReturned([food, l]), 100000);
    });

    test('an unpaid loan you gave still counts', () {
      final l = loan(100000, lent: DateTime(2026, 11, 3));
      expect(l.isLoanCancelledByRepayment, isFalse);
      expect(BudgetCalculator.spent([food, l]), 285000);
      expect(BudgetCalculator.loansReturned([l]), 0);
    });

    test('paid back in a later month stays counted in the month it was lent', () {
      final l = loan(50000, lent: DateTime(2026, 10, 28), paid: DateTime(2026, 11, 2));
      expect(l.isLoanCancelledByRepayment, isFalse);
      expect(BudgetCalculator.spent([l]), 50000);
    });

    test('same month number in another year is not the same month', () {
      final l = loan(50000, lent: DateTime(2025, 11, 28), paid: DateTime(2026, 11, 2));
      expect(l.isLoanCancelledByRepayment, isFalse);
    });

    test('a loan you received is never cancelled (its payment is the expense)', () {
      final l = loan(100000, kind: TransactionKind.income, lent: DateTime(2026, 11, 3), paid: DateTime(2026, 11, 10));
      expect(l.isLoanCancelledByRepayment, isFalse);
      expect(BudgetCalculator.loansReturned([l]), 0);
    });

    test('Insights totals agree with the budget', () {
      final l = loan(100000, lent: DateTime(2026, 11, 3), paid: DateTime(2026, 11, 20));
      expect(SpendingAnalytics.total([food, l]), 185000);
      expect(SpendingAnalytics.dailyTotals([food, l], DateTime(2026, 11))[2], 0);
      expect(SpendingAnalytics.byCategory([food, l]).map((c) => c.categoryId), [1]);
    });
  });
}
