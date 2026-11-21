import '../../core/dates.dart';
import '../../data/models/transaction_entry.dart';
import '../budget/budget_calculator.dart';

class CategoryTotal {
  const CategoryTotal({required this.categoryId, required this.total, required this.count});

  /// null = uncategorized
  final int? categoryId;
  final int total;
  final int count;
}

class PeriodComparison {
  const PeriodComparison({required this.current, required this.previous});

  final int current;
  final int previous;

  int get difference => current - previous;

  /// null when there is nothing to compare against.
  double? get changeRatio => previous == 0 ? null : (current - previous) / previous;
}

/// Pure functions over a list of transactions. Only expenses are counted.
class SpendingAnalytics {
  SpendingAnalytics._();

  /// Spending per day of [month]; index 0 = day 1.
  static List<int> dailyTotals(Iterable<TransactionEntry> txs, DateTime month) {
    final days = Dates.daysInMonth(month);
    final totals = List<int>.filled(days, 0);
    for (final t in txs) {
      if (!t.isExpense) continue;
      if (t.date.year != month.year || t.date.month != month.month) continue;
      totals[t.date.day - 1] += t.amount;
    }
    return totals;
  }

  /// Largest first.
  static List<CategoryTotal> byCategory(Iterable<TransactionEntry> txs) {
    final totals = <int?, int>{};
    final counts = <int?, int>{};
    for (final t in txs) {
      if (!t.isExpense) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? 0) + t.amount;
      counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
    }
    final list = [
      for (final e in totals.entries)
        CategoryTotal(categoryId: e.key, total: e.value, count: counts[e.key]!),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  static int total(Iterable<TransactionEntry> txs) => BudgetCalculator.spent(txs);

  static int totalBetween(Iterable<TransactionEntry> txs, DateTime from, DateTime to) =>
      BudgetCalculator.spent(txs.where((t) => !t.date.isBefore(from) && t.date.isBefore(to)));

  /// This week (Mon..today) vs the same number of days last week.
  static PeriodComparison weekOverWeek(Iterable<TransactionEntry> txs, DateTime now) {
    final thisWeekStart = Dates.startOfWeek(now);
    final tomorrow = Dates.startOfDay(now).add(const Duration(days: 1));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekSamePoint = tomorrow.subtract(const Duration(days: 7));
    return PeriodComparison(
      current: totalBetween(txs, thisWeekStart, tomorrow),
      previous: totalBetween(txs, lastWeekStart, lastWeekSamePoint),
    );
  }

  /// Weekly totals inside [month], split Monday-to-Sunday (partial weeks at
  /// the edges are kept). Returns (label, total) pairs.
  static List<({String label, int total})> weeksOfMonth(Iterable<TransactionEntry> txs, DateTime month) {
    final daily = dailyTotals(txs, month);
    final result = <({String label, int total})>[];
    var start = 1;
    var sum = 0;
    for (var day = 1; day <= daily.length; day++) {
      sum += daily[day - 1];
      final weekday = DateTime(month.year, month.month, day).weekday;
      if (weekday == DateTime.sunday || day == daily.length) {
        result.add((label: start == day ? '$start' : '$start–$day', total: sum));
        start = day + 1;
        sum = 0;
      }
    }
    return result;
  }
}
