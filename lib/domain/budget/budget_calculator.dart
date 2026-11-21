import '../../core/dates.dart';
import '../../data/models/transaction_entry.dart';

enum BudgetLevel { none, ok, warning, exceeded }

/// Budget vs spending for one month (overall or one category).
class BudgetProgress {
  const BudgetProgress({required this.budget, required this.spent});

  /// Centavos. 0 = no budget set.
  final int budget;
  final int spent;

  bool get hasBudget => budget > 0;

  /// Negative when over budget.
  int get remaining => budget - spent;

  /// Spent / budget, not clamped (1.25 = 125%).
  double get ratio => hasBudget ? spent / budget : 0;

  /// Whole percent, rounded down (so 79.9% shows as 79%, not 80%).
  int get percentUsed => hasBudget ? (spent * 100) ~/ budget : 0;

  BudgetLevel get level => BudgetCalculator.levelFor(budget: budget, spent: spent);
}

class BudgetCalculator {
  BudgetCalculator._();

  static const warningPercent = 80;
  static const exceededPercent = 100;

  static BudgetLevel levelFor({required int budget, required int spent}) {
    if (budget <= 0) return BudgetLevel.none;
    // Integer math: spent/budget >= 0.8  <=>  spent*100 >= budget*80
    if (spent * 100 >= budget * exceededPercent) return BudgetLevel.exceeded;
    if (spent * 100 >= budget * warningPercent) return BudgetLevel.warning;
    return BudgetLevel.ok;
  }

  /// Total expenses, optionally for one category. Income is ignored.
  static int spent(Iterable<TransactionEntry> txs, {int? categoryId}) {
    var total = 0;
    for (final t in txs) {
      if (!t.isExpense) continue;
      if (categoryId != null && t.categoryId != categoryId) continue;
      total += t.amount;
    }
    return total;
  }

  /// Which alert thresholds (80, 100) have been reached.
  static List<int> thresholdsReached({required int budget, required int spent}) {
    if (budget <= 0) return const [];
    return [
      if (spent * 100 >= budget * warningPercent) warningPercent,
      if (spent * 100 >= budget * exceededPercent) exceededPercent,
    ];
  }

  /// Thresholds reached that haven't been alerted yet this month.
  static List<int> newAlerts({
    required int budget,
    required int spent,
    required Set<int> alreadySent,
  }) =>
      thresholdsReached(budget: budget, spent: spent)
          .where((t) => !alreadySent.contains(t))
          .toList();

  /// Days of [month] that count for averages: all days for past months,
  /// days so far (including today) for the current month, 0 for future.
  static int daysElapsed(DateTime month, DateTime now) {
    final start = Dates.monthStart(month);
    final end = Dates.monthEnd(month);
    if (!now.isAfter(start) && !Dates.sameDay(now, start)) return 0;
    if (!now.isBefore(end)) return Dates.daysInMonth(month);
    return now.day;
  }

  static int averageDaily({required int spent, required DateTime month, required DateTime now}) {
    final days = daysElapsed(month, now);
    return days == 0 ? 0 : spent ~/ days;
  }

  /// How much can be spent per remaining day (including today) to stay on
  /// budget. 0 when already over.
  static int safeDailySpend({
    required int budget,
    required int spent,
    required DateTime month,
    required DateTime now,
  }) {
    final remaining = budget - spent;
    if (remaining <= 0) return 0;
    final total = Dates.daysInMonth(month);
    final elapsed = daysElapsed(month, now);
    final daysLeft = total - elapsed + 1;
    if (daysLeft <= 0) return 0;
    return remaining ~/ daysLeft;
  }

  /// Simple straight-line forecast of month-end spending.
  static int projectedMonthEnd({required int spent, required DateTime month, required DateTime now}) {
    final days = daysElapsed(month, now);
    if (days == 0) return 0;
    return (spent * Dates.daysInMonth(month)) ~/ days;
  }
}
