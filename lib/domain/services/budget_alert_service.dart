import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../analytics/data_prep.dart';
import '../budget/budget_calculator.dart';
import 'notification_service.dart';

/// Sends a local notification the first time a budget reaches 80% and 100%
/// in a month. Which alerts were sent is remembered in settings, so each
/// one fires once per month.
class BudgetAlertService {
  BudgetAlertService({
    required this._budgets,
    required this._transactions,
    required this._categories,
    required this._settings,
    required this._notifications,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BudgetRepository _budgets;
  final TransactionRepository _transactions;
  final CategoryRepository _categories;
  final SettingsRepository _settings;
  final NotificationService _notifications;
  final DateTime Function() _clock;

  /// Checks the month containing [date]. Only the current month alerts.
  Future<void> checkMonth(DateTime date) async {
    final now = _clock();
    final month = Dates.monthKey(date);
    if (month != Dates.monthKey(now)) return;

    final budgets = await _budgets.ensureMonth(month);
    if (budgets.isEmpty) return;
    // Same cleaned data as the Budget screen, so alerts match what's shown.
    final txs = DataPrep.clean(await _transactions.rawBetween(Dates.monthStart(date), Dates.monthEnd(date))).rows;

    final key = SettingsRepository.budgetAlertKey(month);
    final sent = ((await _settings.get(key)) ?? '').split(',').where((s) => s.isNotEmpty).toSet();
    final symbol = CurrencyInfo.byCode(await _settings.get(SettingsRepository.currency)).symbol;
    final categories = {for (final c in await _categories.all()) c.id: c.name};

    var changed = false;
    for (final b in budgets) {
      final spent = BudgetCalculator.spent(txs, categoryId: b.categoryId);
      final scope = b.categoryId == null ? 'all' : 'c${b.categoryId}';
      final already = {
        for (final s in sent)
          if (s.startsWith('$scope:')) int.tryParse(s.substring(scope.length + 1)) ?? 0,
      };
      final fresh = BudgetCalculator.newAlerts(budget: b.amount, spent: spent, alreadySent: already);
      if (fresh.isEmpty) continue;

      // Only notify the highest new threshold (no 80% + 100% double ping).
      final threshold = fresh.reduce((a, c) => a > c ? a : c);
      final name = b.categoryId == null ? 'Monthly budget' : '${categories[b.categoryId] ?? 'Category'} budget';
      final title = threshold >= 100 ? '$name used up' : '$name at $threshold%';
      final body = 'Spent ${Money.format(spent, symbol: symbol)} of ${Money.format(b.amount, symbol: symbol)}'
          ' this month.';
      await _notifications.showBudgetAlert(
        id: NotificationService.budgetAlertId(b.categoryId, threshold),
        title: title,
        body: body,
      );
      for (final t in fresh) {
        sent.add('$scope:$t');
      }
      changed = true;
    }
    if (changed) await _settings.set(key, sent.join(','));
  }
}
