import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db/default_data.dart';
import '../models/category.dart';

class CategoryRepository {
  CategoryRepository(this._db);
  final Database _db;

  Future<List<Category>> all() async {
    final rows = await _db.query('categories', orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> insert(Category c) async {
    final maxRow = await _db.rawQuery('SELECT MAX(sort_order) AS m FROM categories');
    final next = ((maxRow.first['m'] as int?) ?? 0) + 1;
    return _db.insert('categories', c.copyWith(sortOrder: next).toMap()..remove('id'));
  }

  Future<void> update(Category c) async {
    await _db.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<bool> nameExists(String name, {int? exceptId}) async {
    final rows = await _db.query(
      'categories',
      where: exceptId == null ? 'name = ? COLLATE NOCASE' : 'name = ? COLLATE NOCASE AND id != ?',
      whereArgs: exceptId == null ? [name] : [name, exceptId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// The "Other income" category (where income goes when none is picked).
  /// The "Debt" expense category (created if missing).
  Future<int> debtCategoryId() => DefaultData.ensureDebtCategory(_db);

  /// The "Fees" expense category for transfer fees (created if missing).
  Future<int> feesCategoryId() => DefaultData.ensureFeesCategory(_db);

  /// The "Loan" expense category listed in the Loans section.
  Future<int> loanCategoryId() => DefaultData.ensureLoanCategory(_db);

  /// The "Business / sales" income category for sales added to the budget.
  Future<int> salesCategoryId() => DefaultData.ensureSalesCategory(_db);

  Future<int?> savingsCategoryId() async {
    final rows = await _db.query(
      'categories',
      columns: ['id'],
      where: "kind = 'savings'",
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    await DefaultData.ensureSavingsCategory(_db);
    final recheck = await _db.query('categories', columns: ['id'], where: "kind = 'savings'", limit: 1);
    return recheck.isEmpty ? null : recheck.first['id'] as int;
  }

  Future<int?> otherIncomeId() async {
    final rows = await _db.query(
      'categories',
      columns: ['id'],
      where: "kind = 'income' AND role = 'other'",
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Moves the category's transactions to "Other" (or "Other income") and
  /// deletes it. Its keyword rules and budgets are deleted by ON DELETE CASCADE.
  Future<void> delete(int id) async {
    final rows = await _db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final c = Category.fromMap(rows.first);
    if (c.role != null || id == DefaultData.other) {
      throw StateError('"${c.name}" is built in and cannot be deleted.');
    }
    final target = c.isIncome ? await otherIncomeId() : DefaultData.other;
    await _db.transaction((txn) async {
      await txn.update(
        'transactions',
        {'category_id': target},
        where: 'category_id = ?',
        whereArgs: [id],
      );
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }
}

class RuleRepository {
  RuleRepository(this._db);
  final Database _db;

  Future<List<CategoryRule>> all() async {
    final rows = await _db.query('category_rules', orderBy: 'keyword COLLATE NOCASE');
    return rows.map(CategoryRule.fromMap).toList();
  }

  Future<bool> keywordExists(String keyword, {int? exceptId}) async {
    final rows = await _db.query(
      'category_rules',
      where: exceptId == null ? 'keyword = ? COLLATE NOCASE' : 'keyword = ? COLLATE NOCASE AND id != ?',
      whereArgs: exceptId == null ? [keyword] : [keyword, exceptId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insert(CategoryRule r) => _db.insert('category_rules', r.toMap()..remove('id'));

  Future<void> update(CategoryRule r) async {
    await _db.update('category_rules', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  Future<void> delete(int id) async {
    await _db.delete('category_rules', where: 'id = ?', whereArgs: [id]);
  }
}
