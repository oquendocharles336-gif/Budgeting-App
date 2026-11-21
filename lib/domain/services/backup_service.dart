import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/money.dart';
import '../../data/db/default_data.dart';
import '../../data/db/migrations.dart';
import '../../data/repositories/account_ledger.dart';
import '../../data/repositories/settings_repository.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Replace everything, or add the backup's records next to what's here.
enum RestoreMode { replace, merge }

/// A checked backup, ready to restore.
class BackupData {
  const BackupData({required this.schemaVersion, required this.tables, required this.photos});
  final int schemaVersion;
  final Map<String, List<Map<String, Object?>>> tables;

  /// Photo file name -> base64 of the photo. Photos are decrypted from this
  /// phone's key for the backup (another phone has a different key) and
  /// protected by the backup password instead, like the rest of the file.
  final Map<String, String> photos;

  int count(String table) => tables[table]?.length ?? 0;
}

/// Export to CSV/JSON, full local backup/restore, and "delete all data".
/// Files are written wherever the user chooses; nothing is uploaded.
class BackupService {
  BackupService(this._db);
  final Database _db;

  /// 2 = photos included. Format 1 files (no photos) still restore.
  static const _format = 2;
  static const _appId = 'pitaka';

  /// Insert order (parents before children). Deletes run in reverse.
  /// `transactions.debt_id` points at `debts`, so debts come first.
  static const tables = [
    'categories',
    'cards',
    'category_rules',
    'debts',
    'debt_payments',
    'transactions',
    'budgets',
    'sms_patterns',
    'settings',
    // v7: the business side. (A `pay_later` table in an older backup is
    // ignored: that feature was removed in v9.)
    'capital_entries',
    'inventory_items',
    'products',
    // v8: recipes, orders, and the stock ledger (after orders, which it names).
    'product_ingredients',
    'orders',
    'order_items',
    'stock_movements',
  ];

  /// Every table, minus device-only settings (PIN, photo draft).
  Future<Map<String, List<Map<String, Object?>>>> exportTables() async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in tables) {
      var rows = await _db.query(t);
      if (t == 'settings') {
        rows = rows.where((r) => !SettingsRepository.privateKeys.contains(r['key'])).toList();
      }
      out[t] = rows;
    }
    return out;
  }

  /// Full backup as JSON. [photos]: file name -> base64 photo bytes.
  Future<String> exportJson({Map<String, String> photos = const {}}) async => encode(await exportTables(), photos: photos);

  static String encode(Map<String, List<Map<String, Object?>>> tables, {Map<String, String> photos = const {}}) =>
      const JsonEncoder.withIndent(' ').convert({
        'app': _appId,
        'format': _format,
        'schemaVersion': Migrations.latestVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'tables': tables,
        'photos': photos,
      });

  /// Checks a backup's structure before anything is touched. Throws
  /// [BackupException] with a readable reason.
  static BackupData parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupException('This file is not a valid backup (not JSON).');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != _appId) {
      throw const BackupException('This file is not a Pitaka backup.');
    }
    final format = decoded['format'];
    if (format != 1 && format != _format) {
      throw const BackupException('This backup was made by a different app version.');
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema > Migrations.latestVersion) {
      throw const BackupException('This backup is from a newer version of the app. Update the app first.');
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) throw const BackupException('Backup is missing its data.');
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in tables) {
      final rows = rawTables[t];
      if (rows == null) continue;
      if (rows is! List) throw BackupException('Backup data is damaged ($t).');
      final list = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) throw BackupException('Backup data is damaged ($t).');
        list.add(Map<String, Object?>.from(row));
      }
      out[t] = list;
    }
    final photos = <String, String>{};
    final rawPhotos = decoded['photos'];
    if (rawPhotos != null) {
      if (rawPhotos is! Map<String, dynamic>) throw const BackupException('Backup photos are damaged.');
      for (final e in rawPhotos.entries) {
        final name = e.key;
        // Plain file names only: a crafted backup must not write elsewhere.
        if (e.value is! String || name != p.basename(name) || name.startsWith('.') || name.isEmpty) {
          throw const BackupException('Backup photos are damaged.');
        }
        photos[name] = e.value as String;
      }
    }
    return BackupData(schemaVersion: schema, tables: out, photos: photos);
  }

  /// Replaces all data with a backup (format 1 or 2, photos ignored here).
  Future<void> restoreJson(String json) => restore(parse(json));

  /// Restores [data] in one database transaction: a bad file or any error
  /// leaves the current data untouched (never half-restored).
  ///
  /// [photoPath] turns a photo path saved in the backup into this phone's
  /// path for the same photo (null = no photo).
  Future<void> restore(
    BackupData data, {
    RestoreMode mode = RestoreMode.replace,
    String? Function(String? backupPath)? photoPath,
  }) async {
    String? mapPhoto(Object? old) => old is String ? (photoPath == null ? null : photoPath(old)) : null;
    // Keep this device's PIN / biometric settings.
    final private = await _db.query(
      'settings',
      where: 'key IN (${List.filled(SettingsRepository.privateKeys.length, '?').join(',')})',
      whereArgs: SettingsRepository.privateKeys.toList(),
    );
    try {
      await _db.transaction((txn) async {
        if (mode == RestoreMode.replace) {
          await _replace(txn, data, mapPhoto, private);
        } else {
          await _BackupMerge(txn, data, mapPhoto).run();
        }
        await txn.update('categories', {'role': 'other'}, where: 'id = ? AND role IS NULL', whereArgs: [DefaultData.other]);
        await DefaultData.ensureIncomeCategories(txn);
        await DefaultData.ensureDebtCategory(txn);
        await DefaultData.ensureV7Categories(txn);
        // Old backups can hold the removed "Delivered" statuses.
        await txn.execute("UPDATE orders SET status = 'complete' WHERE status IN ('delivered', 'delivered_unpaid')");
      });
    } on BackupException {
      rethrow;
    } on DatabaseException catch (e) {
      throw BackupException('Backup could not be restored: ${e.toString()}');
    }
  }

  static Future<void> _replace(
    Transaction txn,
    BackupData data,
    String? Function(Object?) mapPhoto,
    List<Map<String, Object?>> private,
  ) async {
    for (final t in tables.reversed) {
      await txn.delete(t);
    }
    await txn.delete('op_keys');
    for (final t in tables) {
      final rows = data.tables[t];
      if (rows == null) continue;
      for (final row in rows) {
        if (t == 'settings' && SettingsRepository.privateKeys.contains(row['key'])) continue;
        final r = Map<String, Object?>.from(row);
        if (t == 'inventory_items' || t == 'products') r['photo_path'] = mapPhoto(r['photo_path']);
        await txn.insert(t, r);
      }
    }
    // Backups from before the stock ledger: their quantity becomes the
    // first ledger row, as the v8 migration does.
    if (data.schemaVersion < 8) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in data.tables['inventory_items'] ?? const <Map<String, Object?>>[]) {
        final q = (row['quantity'] as num?)?.toDouble() ?? 0;
        if (q > 0) {
          await txn.insert('stock_movements', {
            'item_id': row['id'],
            'change': q,
            'reason': 'adjustment',
            'note': 'Starting stock',
            'date': now,
            'created_at': now,
          });
        }
      }
    }
    // Older backups (schema 1) have no SMS patterns.
    if (data.tables['sms_patterns'] == null) {
      for (final p in DefaultData.smsPatterns) {
        await txn.insert('sms_patterns', p.toMap());
      }
    }
    for (final row in private) {
      await txn.insert('settings', row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<String> exportTransactionsCsv() async {
    final rows = await _db.rawQuery('''
      SELECT t.date, t.description, t.amount, t.kind, t.notes, t.source,
             c.name AS category, k.nickname AS card_name, k.last4 AS card_last4
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      LEFT JOIN cards k ON k.id = t.card_id
      ORDER BY t.date DESC, t.id DESC
    ''');
    final fmt = DateFormat('yyyy-MM-dd');
    final out = <List<String>>[
      ['Date', 'Description', 'Amount', 'Type', 'Category', 'Paid with', 'Source', 'Notes'],
      for (final r in rows)
        [
          fmt.format(DateTime.fromMillisecondsSinceEpoch(r['date'] as int)),
          r['description'] as String,
          Money.toInput(r['amount'] as int),
          r['kind'] as String,
          (r['category'] as String?) ?? '',
          r['card_name'] == null ? 'Cash' : '${r['card_name']} ${r['card_last4']}',
          r['source'] as String,
          (r['notes'] as String?) ?? '',
        ],
    ];
    return encodeCsv(out);
  }


  /// Deletes every card, transaction, budget, debt,
  /// business record (capital, stock ledger, inventory, recipes, products,
  /// orders), custom category and rule, and puts back the defaults. Photo
  /// files and their key are deleted by `PhotoService.deleteAll`.
  Future<void> deleteAllData() async {
    await _db.transaction((txn) async {
      for (final t in tables.reversed) {
        if (t == 'settings') continue;
        await txn.delete(t);
      }
      await txn.delete('op_keys');
      await txn.delete(
        'settings',
        where: "key LIKE 'budget_alerts_%' OR key LIKE 'budget_init_%' OR key IN (?, ?, ?)",
        whereArgs: [AccountLedger.cashKey, SettingsRepository.photoDraft, SettingsRepository.photosEncrypted],
      );
      for (final c in DefaultData.categories) {
        await txn.insert('categories', c.toMap());
      }
      await DefaultData.ensureIncomeCategories(txn);
      await DefaultData.ensureDebtCategory(txn);
      await DefaultData.ensureV7Categories(txn);
      for (final r in DefaultData.rules) {
        await txn.insert('category_rules', r.toMap());
      }
      for (final p in DefaultData.smsPatterns) {
        await txn.insert('sms_patterns', p.toMap());
      }
    });
  }

  /// "Clear history": deletes every transaction (expenses, income,
  /// transfers, fees, loans and their payments) in one SQLite transaction.
  ///
  /// Account balances are NOT changed: they already are the real amounts
  /// in each account, and only the record of how they got there goes.
  /// Budgets, debts, cards and business records stay. Business capital
  /// keeps its history (only its link to the deleted transfer is dropped),
  /// and orders already added to the budget stay "added", so their sales
  /// can't be counted a second time.
  Future<void> clearHistory() async {
    await _db.transaction((txn) async {
      await txn.update('capital_entries', {'transaction_id': null}, where: 'transaction_id IS NOT NULL');
      // 0 = "added, transaction cleared" (no transaction has id 0).
      await txn.update('orders', {'budget_tx_id': 0}, where: 'budget_tx_id IS NOT NULL');
      await txn.delete('transactions');
      await txn.delete('op_keys');
      // Alerts are counted per month from transactions; let them fire again.
      await txn.delete('settings', where: "key LIKE 'budget_alerts_%'");
    });
  }

  /// RFC 4180 CSV writer.
  static String encodeCsv(List<List<String>> rows) {
    String esc(String v) {
      if (v.contains(RegExp(r'[",\r\n]'))) return '"${v.replaceAll('"', '""')}"';
      return v;
    }

    return rows.map((r) => r.map(esc).join(',')).join('\r\n');
  }
}

/// "Merge": the backup's records are added next to the current ones with
/// new ids (every link between tables is re-pointed). Categories with the
/// same name are reused; rules, budgets and bank-reference transactions
/// already here are not added twice. Settings and SMS patterns stay as
/// they are. Cash balance stays as it is, so merged cash rows are marked as
/// not moving it (editing them later won't change Cash twice).
class _BackupMerge {
  _BackupMerge(this.txn, this.data, this.mapPhoto);
  final Transaction txn;
  final BackupData data;
  final String? Function(Object?) mapPhoto;
  final _ids = <String, Map<int, int>>{};

  List<Map<String, Object?>> _rows(String t) => data.tables[t] ?? const [];
  int? _map(String table, Object? old) {
    if (old is! int) return null;
    final ids = _ids[table];
    return ids == null ? null : ids[old];
  }
  void _put(String table, Object? old, int id) {
    if (old is int) (_ids[table] ??= {})[old] = id;
  }

  Map<String, Object?> _copy(Map<String, Object?> row) => Map<String, Object?>.from(row)..remove('id');

  Future<void> run() async {
    await _categories();
    for (final r in _rows('cards')) {
      _put('cards', r['id'], await txn.insert('cards', _copy(r)));
    }
    for (final r in _rows('category_rules')) {
      final cat = _map('categories', r['category_id']);
      if (cat == null) continue;
      final exists = await txn.query('category_rules', where: 'keyword = ? COLLATE NOCASE', whereArgs: [r['keyword']], limit: 1);
      if (exists.isNotEmpty) continue;
      await txn.insert('category_rules', _copy(r)..['category_id'] = cat);
    }
    for (final r in _rows('debts')) {
      _put('debts', r['id'], await txn.insert('debts', _copy(r)));
    }
    for (final r in _rows('debt_payments')) {
      final debt = _map('debts', r['debt_id']);
      if (debt == null) continue;
      await txn.insert('debt_payments', _copy(r)..['debt_id'] = debt);
    }
    await _transactions();
    for (final r in _rows('budgets')) {
      final cat = r['category_id'] == null ? null : _map('categories', r['category_id']);
      if (r['category_id'] != null && cat == null) continue;
      final exists = await txn.query(
        'budgets',
        where: 'month = ? AND IFNULL(category_id, 0) = ?',
        whereArgs: [r['month'], cat ?? 0],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;
      await txn.insert('budgets', _copy(r)..['category_id'] = cat);
    }
    for (final r in _rows('capital_entries')) {
      await txn.insert('capital_entries', _copy(r)..['transaction_id'] = _map('transactions', r['transaction_id']));
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in _rows('inventory_items')) {
      final id = await txn.insert('inventory_items', _copy(r)..['photo_path'] = mapPhoto(r['photo_path']));
      _put('inventory_items', r['id'], id);
      final q = (r['quantity'] as num?)?.toDouble() ?? 0;
      if (data.schemaVersion < 8 && q > 0) {
        await txn.insert('stock_movements',
            {'item_id': id, 'change': q, 'reason': 'adjustment', 'note': 'Starting stock', 'date': now, 'created_at': now});
      }
    }
    for (final r in _rows('products')) {
      _put('products', r['id'], await txn.insert('products', _copy(r)..['photo_path'] = mapPhoto(r['photo_path'])));
    }
    for (final r in _rows('product_ingredients')) {
      final product = _map('products', r['product_id']);
      final item = _map('inventory_items', r['item_id']);
      if (product == null || item == null) continue;
      await txn.insert('product_ingredients', _copy(r)
        ..['product_id'] = product
        ..['item_id'] = item);
    }
    for (final r in _rows('orders')) {
      _put('orders', r['id'], await txn.insert('orders', _copy(r)..['budget_tx_id'] = _map('transactions', r['budget_tx_id'])));
    }
    for (final r in _rows('order_items')) {
      final order = _map('orders', r['order_id']);
      if (order == null) continue;
      await txn.insert('order_items', _copy(r)
        ..['order_id'] = order
        ..['product_id'] = _map('products', r['product_id']));
    }
    for (final r in _rows('stock_movements')) {
      final item = _map('inventory_items', r['item_id']);
      if (item == null) continue;
      await txn.insert('stock_movements', _copy(r)
        ..['item_id'] = item
        ..['order_id'] = _map('orders', r['order_id']));
    }
  }

  Future<void> _categories() async {
    for (final r in _rows('categories')) {
      final name = '${r['name']}';
      final kind = r['kind'] ?? 'expense';
      final same = await txn.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
      if (same.isNotEmpty && (same.first['kind'] ?? 'expense') == kind) {
        _put('categories', r['id'], same.first['id'] as int);
        continue;
      }
      final row = _copy(r);
      if (same.isNotEmpty) row['name'] = '$name (restored)';
      final again = await txn.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [row['name']], limit: 1);
      if (again.isNotEmpty) {
        _put('categories', r['id'], again.first['id'] as int);
        continue;
      }
      // Built-in roles stay with the categories already here.
      if (r['role'] != null) {
        final role = await txn.query('categories', where: 'role = ?', whereArgs: [r['role']], limit: 1);
        if (role.isNotEmpty) row['role'] = null;
      }
      _put('categories', r['id'], await txn.insert('categories', row));
    }
  }

  Future<void> _transactions() async {
    final fees = <int, Object?>{}; // new id -> old fee_of_id
    final loanPayments = <int, Object?>{}; // new id -> old loan_payment_of_id
    for (final r in _rows('transactions')) {
      final row = _copy(r)
        ..['category_id'] = _map('categories', r['category_id'])
        ..['debt_id'] = _map('debts', r['debt_id'])
        ..['fee_of_id'] = null;
      if (r.containsKey('loan_payment_of_id')) row['loan_payment_of_id'] = null;
      // An account that wasn't restored: skip rather than move the row to Cash.
      if (r['card_id'] != null && (row['card_id'] = _map('cards', r['card_id'])) == null) continue;
      if (r['to_card_id'] != null && (row['to_card_id'] = _map('cards', r['to_card_id'])) == null) continue;
      final ext = r['external_id'];
      if (ext != null) {
        final dup = await txn.query(
          'transactions',
          columns: ['id'],
          where: 'IFNULL(card_id, 0) = ? AND external_id = ?',
          whereArgs: [row['card_id'] ?? 0, ext],
          limit: 1,
        );
        if (dup.isNotEmpty) {
          _put('transactions', r['id'], dup.first['id'] as int);
          continue;
        }
      }
      final cashSide = (row['card_id'] == null && r['from_capital'] != 1) ||
          (r['kind'] == 'transfer' && row['to_card_id'] == null && r['to_capital'] != 1);
      if (cashSide) row['affects_balance'] = 0;
      final id = await txn.insert('transactions', row);
      _put('transactions', r['id'], id);
      if (r['fee_of_id'] != null) fees[id] = r['fee_of_id'];
      if (r['loan_payment_of_id'] != null) loanPayments[id] = r['loan_payment_of_id'];
    }
    for (final e in fees.entries) {
      await txn.update('transactions', {'fee_of_id': _map('transactions', e.value)}, where: 'id = ?', whereArgs: [e.key]);
    }
    for (final e in loanPayments.entries) {
      await txn.update('transactions', {'loan_payment_of_id': _map('transactions', e.value)}, where: 'id = ?', whereArgs: [e.key]);
    }
  }
}
