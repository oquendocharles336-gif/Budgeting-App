import 'package:sqflite/sqflite.dart';

import '../models/budget.dart';

class BudgetRepository {
  BudgetRepository(this._db);
  final Database _db;

  Future<List<Budget>> forMonth(String month) async {
    final rows = await _db.query('budgets', where: 'month = ?', whereArgs: [month]);
    return rows.map(Budget.fromMap).toList();
  }

  /// Settings key marking that a month's budgets were set up, so removing
  /// every budget in a month doesn't bring last month's back.
  static String _initKey(String month) => 'budget_init_$month';

  Future<bool> _isInitialized(DatabaseExecutor db, String month) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [_initKey(month)], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> _markInitialized(DatabaseExecutor db, String month) async {
    await db.insert('settings', {'key': _initKey(month), 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Makes sure [month] has budgets. A new month starts with the same
  /// amounts as the most recent earlier month (spending starts at zero
  /// because it's counted per month). Older months stay as history.
  Future<List<Budget>> ensureMonth(String month) async {
    final existing = await forMonth(month);
    if (existing.isNotEmpty) return existing;
    if (await _isInitialized(_db, month)) return const [];

    final prev = await _db.rawQuery(
      'SELECT MAX(month) AS m FROM budgets WHERE month < ?',
      [month],
    );
    final prevMonth = prev.first['m'] as String?;
    if (prevMonth == null) return const [];

    final source = await forMonth(prevMonth);
    await _db.transaction((txn) async {
      await _markInitialized(txn, month);
      for (final b in source) {
        await txn.insert('budgets', {
          'month': month,
          'category_id': b.categoryId,
          'amount': b.amount,
        });
      }
    });
    return forMonth(month);
  }

  /// Sets (or clears, when [amount] is null or 0) a budget.
  /// [categoryId] null = overall budget.
  Future<void> setBudget(String month, int? categoryId, int? amount) async {
    final where = categoryId == null ? 'month = ? AND category_id IS NULL' : 'month = ? AND category_id = ?';
    final args = categoryId == null ? [month] : [month, categoryId];
    await _db.transaction((txn) async {
      await _markInitialized(txn, month);
      await txn.delete('budgets', where: where, whereArgs: args);
      if (amount != null && amount > 0) {
        await txn.insert('budgets', {'month': month, 'category_id': categoryId, 'amount': amount});
      }
    });
  }

  /// Months that have an overall budget, newest first.
  Future<List<Budget>> overallHistory() async {
    final rows = await _db.query(
      'budgets',
      where: 'category_id IS NULL',
      orderBy: 'month DESC',
    );
    return rows.map(Budget.fromMap).toList();
  }
}
