import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../../data/models/debt.dart';
import '../../data/models/payment_card.dart';
import '../../data/models/sms_pattern.dart';
import '../../data/models/transaction_entry.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/analytics/data_prep.dart';
import '../../domain/analytics/insights_range.dart';
import '../../domain/analytics/spending_analytics.dart';
import '../../domain/budget/budget_calculator.dart';
import '../../domain/services/phone_access_service.dart';
import 'core_providers.dart';
import 'optimistic_providers.dart';

// Every provider below watches dataRevisionProvider, so a single bump()
// after a write refreshes everything on screen.

final cardsProvider = FutureProvider<List<PaymentCard>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(cardRepositoryProvider).all();
});

/// Includes archived cards, keyed by id (for labelling old transactions).
final cardMapProvider = FutureProvider<Map<int, PaymentCard>>((ref) async {
  ref.watch(dataRevisionProvider);
  final cards = await ref.watch(cardRepositoryProvider).all(includeArchived: true);
  return {for (final c in cards) c.id!: c};
});

/// Money in Cash (the account with no card).
final cashBalanceProvider = FutureProvider<int>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(cardRepositoryProvider).cashBalance();
});

/// Account totals added up in SQL (SUM), not in Dart.
final accountTotalsProvider = FutureProvider<AccountTotals>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(cardRepositoryProvider).balanceTotals();
});

/// Totals shown on Home, Budget and the Wallets tab.
///
/// Available balance = Cash + every debit / prepaid / e-wallet balance.
/// Credit cards are left out: available credit is borrowed money, not the
/// user's own, so it is shown on its own line instead.
class BalanceSummary {
  const BalanceSummary({required this.cash, required this.accounts, this.totals = const AccountTotals()});
  final int cash;

  /// Active (not archived) accounts.
  final List<PaymentCard> accounts;

  /// SUM totals of [accounts], from the database.
  final AccountTotals totals;

  /// Debit, prepaid and e-wallet balances together (the second box).
  int get cardsAndWallets => totals.own;

  /// How many accounts are in [cardsAndWallets].
  int get cardsAndWalletsCount => totals.ownCount;

  int get available => cash + totals.own;

  int get availableCredit => totals.credit;
  bool get hasCredit => totals.creditCount > 0;
}

final balanceSummaryProvider = FutureProvider<BalanceSummary>((ref) async {
  final cash = await ref.watch(cashBalanceProvider.future);
  final accounts = await ref.watch(cardsProvider.future);
  final totals = await ref.watch(accountTotalsProvider.future);
  return BalanceSummary(cash: cash, accounts: accounts, totals: totals);
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(categoryRepositoryProvider).all();
});

final categoryMapProvider = FutureProvider<Map<int, Category>>((ref) async {
  final list = await ref.watch(categoriesProvider.future);
  return {for (final c in list) c.id!: c};
});

final rulesProvider = FutureProvider<List<CategoryRule>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(ruleRepositoryProvider).all();
});

final smsPatternsProvider = FutureProvider<List<SmsPattern>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(smsPatternRepositoryProvider).all();
});

// -----------------------------------------------------------------------------
// Transactions list with filters
// -----------------------------------------------------------------------------

class TransactionFilterController extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void set(TransactionFilter f) => state = f;
  void clear() => state = const TransactionFilter();
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterController, TransactionFilter>(TransactionFilterController.new);

final _filteredBaseProvider = FutureProvider<List<TransactionEntry>>((ref) {
  ref.watch(dataRevisionProvider);
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(transactionRepositoryProvider).query(filter, limit: 1000);
});

/// The Activity list, with saves still in progress shown at once.
final filteredTransactionsProvider = FutureProvider<List<TransactionEntry>>((ref) async {
  final base = await ref.watch(_filteredBaseProvider.future);
  final filter = ref.watch(transactionFilterProvider);
  return withPending(base, ref.watch(pendingTransactionsProvider), matches: (t) => matchesFilter(t, filter));
});

final _recentBaseProvider = FutureProvider<List<TransactionEntry>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepositoryProvider).recent(limit: 6);
});

final recentTransactionsProvider = FutureProvider<List<TransactionEntry>>((ref) async {
  final base = await ref.watch(_recentBaseProvider.future);
  return withPending(base, ref.watch(pendingTransactionsProvider), limit: 6);
});

final cardTransactionsProvider = FutureProvider.family<List<TransactionEntry>, int>((ref, cardId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepositoryProvider).query(TransactionFilter(cardId: cardId), limit: 500);
});

// -----------------------------------------------------------------------------
// Debts
// -----------------------------------------------------------------------------

final debtsProvider = FutureProvider<List<DebtStatus>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(debtRepositoryProvider).allStatuses();
});

final debtPaymentsProvider = FutureProvider.family<List<DebtPayment>, int>((ref, debtId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(debtRepositoryProvider).payments(debtId);
});

/// Open debts and unpaid loans, counted with one SQL query and cached here
/// (never in build()). It refreshes with every write (dataRevisionProvider),
/// so adding, paying or deleting a debt or loan updates the badge.
final openDebtLoanCountsProvider = FutureProvider<OpenDebtLoanCounts>((ref) async {
  ref.watch(dataRevisionProvider);
  final c = await ref.watch(debtRepositoryProvider).openCounts();
  return OpenDebtLoanCounts(debts: c.debts, loans: c.loans);
});

class OpenDebtLoanCounts {
  const OpenDebtLoanCounts({this.debts = 0, this.loans = 0});

  /// Debts the user still owes (payables).
  final int debts;

  /// "Loan" transactions not marked paid (borrowed or lent).
  final int loans;

  int get total => debts + loans;

  @override
  bool operator ==(Object other) => other is OpenDebtLoanCounts && other.debts == debts && other.loans == loans;

  @override
  int get hashCode => Object.hash(debts, loans);
}

// -----------------------------------------------------------------------------
// Phone permissions ("Allow" buttons)
// -----------------------------------------------------------------------------

/// What the phone allows Pitaka right now. Read once per unlock (a change
/// made in the phone's settings by hand is seen after the app locks and
/// opens again) and refreshed by the "Allow" buttons.
final phoneAccessProvider = FutureProvider<PhoneAccessStatus>((ref) {
  return ref.watch(phoneAccessServiceProvider).status();
});

/// What Home's "Allow" card needs to know, besides [phoneAccessProvider].
class PhoneAccessNeeds {
  const PhoneAccessNeeds({required this.smsInUse, required this.snoozedUntil});

  /// The user turned on SMS import before, so losing it matters.
  final bool smsInUse;

  /// "Not now" was tapped: hidden until then.
  final DateTime? snoozedUntil;
}

final phoneAccessNeedsProvider = FutureProvider<PhoneAccessNeeds>((ref) async {
  ref.watch(dataRevisionProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  final sms = await settings.get(SettingsRepository.smsEnabled);
  final until = int.tryParse(await settings.get(SettingsRepository.phoneAccessSnoozedUntil) ?? '');
  return PhoneAccessNeeds(
    smsInUse: sms == '1',
    snoozedUntil: until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
  );
});

// -----------------------------------------------------------------------------
// Loans
// -----------------------------------------------------------------------------

/// Transactions in the "Loan" category, unpaid first.
final loansProvider = FutureProvider<List<TransactionEntry>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionServiceProvider).loans();
});

/// The payment expense of each paid loan (loan id -> payment), for the
/// "Paid with" line in the loan history.
final loanPaymentsProvider = FutureProvider<Map<int, TransactionEntry>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionServiceProvider).loanPayments();
});

// -----------------------------------------------------------------------------
// Month selection shared by Budget and Analytics
// -----------------------------------------------------------------------------

class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() => Dates.monthStart(DateTime.now());

  void set(DateTime month) => state = Dates.monthStart(month);
  void previous() => state = Dates.previousMonth(state);
  void next() => state = Dates.nextMonth(state);
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(SelectedMonth.new);

// -----------------------------------------------------------------------------
// Budget summary for one month ("YYYY-MM")
// -----------------------------------------------------------------------------

class CategoryBudgetRow {
  const CategoryBudgetRow({required this.category, required this.progress});
  final Category category;
  final BudgetProgress progress;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.transactions,
    required this.overall,
    required this.categoryRows,
    required this.income,
    this.loansReturned = 0,
    this.spentByAccount = const {},
    this.prep = PrepReport.empty,
  });

  /// What the data-prep step cleaned for these totals.
  final PrepReport prep;

  /// This month's spending by "Paid with" account (null = Cash), biggest
  /// first. Every expense counts in the budget whatever it was paid with.
  final Map<int?, int> spentByAccount;

  final DateTime month;
  final List<TransactionEntry> transactions;
  final BudgetProgress overall;

  /// Categories with a budget or with spending, budgets first.
  final List<CategoryBudgetRow> categoryRows;
  final int income;

  /// Loans you gave this month that came back this month, so they aren't
  /// counted as spending ("Loans returned this month").
  final int loansReturned;
}

/// What a month's summary is computed from (database side).
typedef _MonthBase = ({List<Budget> budgets, List<Category> categories, PreparedData prepared});

final _monthBaseProvider = FutureProvider.family<_MonthBase, String>((ref, monthKey) async {
  ref.watch(dataRevisionProvider);
  final month = Dates.parseMonthKey(monthKey);
  final now = DateTime.now();
  final budgetRepo = ref.watch(budgetRepositoryProvider);

  // Only roll budgets forward into the current or future months, not
  // into old months the user is just browsing.
  final List<Budget> budgets = month.isBefore(Dates.monthStart(now))
      ? await budgetRepo.forMonth(monthKey)
      : await budgetRepo.ensureMonth(monthKey);
  final categories = await ref.watch(categoriesProvider.future);
  // Clean first (missing values, duplicates, formats); every total below
  // uses the cleaned rows.
  final prepared = DataPrep.clean(
    await ref.watch(transactionRepositoryProvider).rawBetween(month, Dates.monthEnd(month)),
    knownCategoryIds: {for (final c in categories) c.id!},
  );
  return (budgets: budgets, categories: categories, prepared: prepared);
});

/// Budget vs spending for one month. Budget edits and transactions still
/// being saved (optimistic UI) are applied on top, so the budget and the
/// remaining amount change the moment a transaction is added, edited or
/// deleted, whatever account it was paid with.
final monthSummaryProvider = FutureProvider.family<MonthSummary, String>((ref, monthKey) async {
  final base = await ref.watch(_monthBaseProvider(monthKey).future);
  final pending = ref.watch(pendingBudgetsProvider);
  final month = Dates.parseMonthKey(monthKey);
  final monthEnd = Dates.monthEnd(month);
  final categories = base.categories;
  final prepared = base.prepared;
  final txs = withPending(
    prepared.rows,
    ref.watch(pendingTransactionsProvider),
    matches: (t) => !t.date.isBefore(month) && t.date.isBefore(monthEnd),
  );

  var overallBudget = base.budgets.where((b) => b.isOverall).fold<int>(0, (a, b) => a + b.amount);
  final byCat = {for (final b in base.budgets.where((b) => !b.isOverall)) b.categoryId!: b.amount};
  for (final e in pending.entries) {
    final [m, cat] = e.key.split('|');
    if (m != monthKey) continue;
    if (cat == 'all') {
      overallBudget = e.value ?? 0;
    } else {
      final id = int.parse(cat);
      if (e.value == null) {
        byCat.remove(id);
      } else {
        byCat[id] = e.value!;
      }
    }
  }

  final rows = <CategoryBudgetRow>[
    // Budgets are for spending, so income categories are left out.
    for (final c in categories.where((c) => !c.isIncome))
      CategoryBudgetRow(
        category: c,
        progress: BudgetProgress(
          budget: byCat[c.id] ?? 0,
          spent: BudgetCalculator.spent(txs, categoryId: c.id),
        ),
      ),
  ]
    ..removeWhere((r) => !r.progress.hasBudget && r.progress.spent == 0)
    ..sort((a, b) {
      if (a.progress.hasBudget != b.progress.hasBudget) return a.progress.hasBudget ? -1 : 1;
      return b.progress.spent.compareTo(a.progress.spent);
    });

  return MonthSummary(
    month: month,
    transactions: txs,
    overall: BudgetProgress(budget: overallBudget, spent: BudgetCalculator.spent(txs)),
    categoryRows: rows,
    income: txs.where((t) => t.isIncome).fold<int>(0, (a, t) => a + t.amount),
    loansReturned: BudgetCalculator.loansReturned(txs),
    spentByAccount: _spentByAccount(txs),
    prep: prepared.report,
  );
});

Map<int?, int> _spentByAccount(List<TransactionEntry> txs) {
  final totals = <int?, int>{};
  for (final t in txs) {
    if (!t.isExpense || t.isLoanCancelledByRepayment) continue;
    totals[t.cardId] = (totals[t.cardId] ?? 0) + t.amount;
  }
  final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in sorted) e.key: e.value};
}

class BudgetHistoryItem {
  const BudgetHistoryItem({required this.month, required this.progress});
  final DateTime month;
  final BudgetProgress progress;
}

/// Past months that had an overall budget, newest first.
final budgetHistoryProvider = FutureProvider<List<BudgetHistoryItem>>((ref) async {
  ref.watch(dataRevisionProvider);
  final history = await ref.watch(budgetRepositoryProvider).overallHistory();
  final txRepo = ref.watch(transactionRepositoryProvider);
  final items = <BudgetHistoryItem>[];
  for (final b in history.take(12)) {
    final m = Dates.parseMonthKey(b.month);
    final txs = DataPrep.clean(await txRepo.rawBetween(m, Dates.monthEnd(m))).rows;
    items.add(BudgetHistoryItem(
      month: m,
      progress: BudgetProgress(budget: b.amount, spent: BudgetCalculator.spent(txs)),
    ));
  }
  return items;
});

// -----------------------------------------------------------------------------
// Analytics for one month
// -----------------------------------------------------------------------------

class AnalyticsData {
  const AnalyticsData({
    required this.month,
    required this.daily,
    required this.byCategory,
    required this.total,
    required this.previousMonthTotal,
    required this.averageDaily,
    required this.week,
    required this.weeks,
    required this.transactionCount,
    this.prep = PrepReport.empty,
  });

  final PrepReport prep;

  final DateTime month;
  final List<int> daily;
  final List<CategoryTotal> byCategory;
  final int total;
  final int previousMonthTotal;
  final int averageDaily;

  /// This week vs last week (always relative to today).
  final PeriodComparison week;
  final List<({String label, int total})> weeks;
  final int transactionCount;

  PeriodComparison get monthComparison => PeriodComparison(current: total, previous: previousMonthTotal);
}

/// Months Insights may show: from the first month with spending to now.
final insightsRangeProvider = FutureProvider<InsightsRange>((ref) async {
  ref.watch(dataRevisionProvider);
  final earliest = await ref.watch(transactionRepositoryProvider).earliestExpenseDate();
  return InsightsRange.from(earliest, DateTime.now());
});

final analyticsProvider = FutureProvider.family<AnalyticsData, String>((ref, monthKey) async {
  ref.watch(dataRevisionProvider);
  final month = Dates.parseMonthKey(monthKey);
  final now = DateTime.now();
  final repo = ref.watch(transactionRepositoryProvider);

  final known = {for (final c in await ref.watch(categoriesProvider.future)) c.id!};
  PreparedData prep(List<Map<String, Object?>> raw) => DataPrep.clean(raw, knownCategoryIds: known);
  final prepared = prep(await repo.rawBetween(month, Dates.monthEnd(month)));
  final txs = prepared.rows;
  final prevMonth = Dates.previousMonth(month);
  final prevTxs = prep(await repo.rawBetween(prevMonth, month)).rows;
  final weekStart = Dates.startOfWeek(now).subtract(const Duration(days: 7));
  final weekTxs = prep(await repo.rawBetween(weekStart, Dates.startOfDay(now).add(const Duration(days: 1)))).rows;

  final total = SpendingAnalytics.total(txs);
  return AnalyticsData(
    month: month,
    daily: SpendingAnalytics.dailyTotals(txs, month),
    byCategory: SpendingAnalytics.byCategory(txs),
    total: total,
    previousMonthTotal: SpendingAnalytics.total(prevTxs),
    averageDaily: BudgetCalculator.averageDaily(spent: total, month: month, now: now),
    week: SpendingAnalytics.weekOverWeek(weekTxs, now),
    weeks: SpendingAnalytics.weeksOfMonth(txs, month),
    transactionCount: txs.where((t) => t.isExpense).length,
    prep: prepared.report,
  );
});
