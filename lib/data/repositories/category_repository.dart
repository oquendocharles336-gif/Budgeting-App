import 'package:sqflite/sqflite.dart';

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

  /// Moves the category's transactions to "Other" and deletes it.
  /// Its keyword rules and budgets are deleted by ON DELETE CASCADE.
  Future<void> delete(int id) async {
    if (id == DefaultData.other) {
      throw StateError('The "Other" category cannot be deleted.');
    }
    await _db.transaction((txn) async {
      await txn.update(
        'transactions',
        {'category_id': DefaultData.other},
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
