import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/money.dart';
import '../../data/db/default_data.dart';
import '../../data/db/migrations.dart';
import '../../data/repositories/settings_repository.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Export to CSV/JSON, full local backup/restore, and "delete all data".
/// Files are written wherever the user chooses; nothing is uploaded.
class BackupService {
  BackupService(this._db);
  final Database _db;

  static const _format = 1;
  static const _appId = 'pitaka';

  /// Insert order (parents before children). Deletes run in reverse.
  static const _tables = [
    'categories',
    'cards',
    'category_rules',
    'transactions',
    'debts',
    'debt_payments',
    'budgets',
    'sms_patterns',
    'settings',
  ];

  /// Full backup as JSON (every table except device-only settings like the PIN).
  Future<String> exportJson() async {
    final tables = <String, Object?>{};
    for (final t in _tables) {
      var rows = await _db.query(t);
      if (t == 'settings') {
        rows = rows.where((r) => !SettingsRepository.privateKeys.contains(r['key'])).toList();
      }
      tables[t] = rows;
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': _appId,
      'format': _format,
      'schemaVersion': Migrations.latestVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }

  /// Replaces all data with a backup. Runs in one database transaction, so
  /// a bad file leaves the current data untouched.
  Future<void> restoreJson(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupException('This file is not a valid backup (not JSON).');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != _appId) {
      throw const BackupException('This file is not a Pitaka backup.');
    }
    if (decoded['format'] != _format) {
      throw const BackupException('This backup was made by a different app version.');
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema > Migrations.latestVersion) {
      throw const BackupException('This backup is from a newer version of the app. Update the app first.');
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const BackupException('Backup is missing its data.');
    }

    // Keep this device's PIN / biometric settings.
    final private = await _db.query(
      'settings',
      where: 'key IN (${List.filled(SettingsRepository.privateKeys.length, '?').join(',')})',
      whereArgs: SettingsRepository.privateKeys.toList(),
    );

    try {
      await _db.transaction((txn) async {
        for (final t in _tables.reversed) {
          await txn.delete(t);
        }
        for (final t in _tables) {
          final rows = tables[t];
          if (rows == null) continue;
          if (rows is! List) throw const BackupException('Backup data is damaged.');
          for (final row in rows) {
            if (row is! Map<String, dynamic>) throw const BackupException('Backup data is damaged.');
            if (t == 'settings' && SettingsRepository.privateKeys.contains(row['key'])) continue;
            await txn.insert(t, row);
          }
        }
        // Older backups (schema 1) have no SMS patterns.
        if (tables['sms_patterns'] == null) {
          for (final p in DefaultData.smsPatterns) {
            await txn.insert('sms_patterns', p.toMap());
          }
        }
        for (final row in private) {
          await txn.insert('settings', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } on BackupException {
      rethrow;
    } on DatabaseException catch (e) {
      throw BackupException('Backup could not be restored: ${e.toString()}');
    }
  }

  /// All transactions as CSV, newest first.
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

  /// Deletes every card, transaction, budget, debt, custom category and
  /// rule, and puts back the defaults. App preferences (theme, currency,
  /// PIN, terms acceptance) are kept: they're settings, not data, and
  /// wiping the PIN here would lock the user out.
  Future<void> deleteAllData() async {
    await _db.transaction((txn) async {
      for (final t in _tables.reversed) {
        if (t == 'settings') continue;
        await txn.delete(t);
      }
      await txn.delete('settings', where: "key LIKE 'budget_alerts_%' OR key LIKE 'budget_init_%'");
      for (final c in DefaultData.categories) {
        await txn.insert('categories', c.toMap());
      }
      for (final r in DefaultData.rules) {
        await txn.insert('category_rules', r.toMap());
      }
      for (final p in DefaultData.smsPatterns) {
        await txn.insert('sms_patterns', p.toMap());
      }
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
