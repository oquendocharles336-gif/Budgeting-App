import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/transaction_entry.dart';
import 'account_ledger.dart';

class TransactionRepository {
  TransactionRepository(this._db);
  final Database _db;

  /// SQLite allows at most 999 `?` parameters per statement on old Android.
  static const _chunk = 500;

  Future<List<TransactionEntry>> query(
    TransactionFilter filter, {
    int? limit,
    int? offset,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (filter.cardId != null) {
      // Transfers into the card count as "on" it too.
      where.add('(card_id = ? OR to_card_id = ?)');
      args
        ..add(filter.cardId)
        ..add(filter.cardId);
    } else if (filter.cashOnly) {
      where.add("(card_id IS NULL OR (kind = 'transfer' AND to_card_id IS NULL))");
    }
    if (filter.categoryId != null) {
      where.add('category_id = ?');
      args.add(filter.categoryId);
    }
    if (filter.kind != null) {
      where.add('kind = ?');
      args.add(filter.kind!.name);
    }
    if (filter.from != null) {
      where.add('date >= ?');
      args.add(filter.from!.millisecondsSinceEpoch);
    }
    if (filter.to != null) {
      where.add('date < ?');
      args.add(filter.to!.millisecondsSinceEpoch);
    }
    final search = filter.search?.trim();
    if (search != null && search.isNotEmpty) {
      where.add("(description LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\')");
      final like = '%${_escapeLike(search)}%';
      args
        ..add(like)
        ..add(like);
    }
    final rows = await _db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(TransactionEntry.fromMap).toList();
  }

  Future<List<TransactionEntry>> between(DateTime from, DateTime to) =>
      query(TransactionFilter(from: from, to: to));

  /// Raw rows for [from, to), for the data-prep (cleaning) step that runs
  /// before charts and totals. Not converted to [TransactionEntry], so bad
  /// values can be handled instead of throwing.
  Future<List<Map<String, Object?>>> rawBetween(DateTime from, DateTime to) => _db.query(
        'transactions',
        where: 'date >= ? AND date < ?',
        whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
        orderBy: 'date DESC, id DESC',
      );

  Future<List<TransactionEntry>> recent({int limit = 5}) =>
      query(const TransactionFilter(), limit: limit);

  Future<TransactionEntry?> byId(int id) async {
    final rows = await _db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : TransactionEntry.fromMap(rows.first);
  }

  /// Saves [tx] and, if it [TransactionEntry.affectsBalance], moves the
  /// account balances, in one SQLite transaction.
  Future<int> insert(TransactionEntry tx) => _db.transaction((txn) async {
        final id = await txn.insert('transactions', tx.toMap()..remove('id'));
        await AccountLedger.apply(txn, tx);
        return id;
      });

  /// Inserts all rows in one database transaction. Returns how many were saved.
  Future<int> insertMany(List<TransactionEntry> txs) async {
    if (txs.isEmpty) return 0;
    return _db.transaction((txn) async {
      var count = 0;
      for (final t in txs) {
        await txn.insert('transactions', t.toMap()..remove('id'));
        await AccountLedger.apply(txn, t);
        count++;
      }
      return count;
    });
  }

  /// Saves the edit. The old row's balance change is undone and the new one
  /// applied (amount, kind or account may all have changed), atomically.
  Future<void> update(TransactionEntry tx) => _db.transaction((txn) async {
        final old = await _byId(txn, tx.id!);
        if (old == null) throw StateError('Transaction ${tx.id} no longer exists');
        await AccountLedger.apply(txn, old, sign: -1);
        // Whether a row moves balances is fixed when it is created.
        final next = tx.copyWith(affectsBalance: old.affectsBalance);
        await txn.update('transactions', next.toMap(), where: 'id = ?', whereArgs: [tx.id]);
        await AccountLedger.apply(txn, next);
      });

  /// Deletes the row and gives its money back to (or takes it from) the account.
  Future<void> delete(int id) => _db.transaction((txn) async {
        final old = await _byId(txn, id);
        if (old == null) return;
        await AccountLedger.apply(txn, old, sign: -1);
        await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
      });

  static Future<TransactionEntry?> _byId(DatabaseExecutor db, int id) async {
    final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : TransactionEntry.fromMap(rows.first);
  }

  /// Scoped external IDs (`cardId|externalId`, or `cash|externalId`) already saved for
  /// the given cards. Pass null in [cardIds] for cash.
  Future<Set<String>> existingExternalIds(Iterable<int?> cardIds) async {
    final ids = cardIds.toSet();
    final result = <String>{};
    final nonNull = ids.whereType<int>().toList();
    for (var i = 0; i < nonNull.length; i += _chunk) {
      final part = nonNull.sublist(i, math.min(i + _chunk, nonNull.length));
      final rows = await _db.rawQuery(
        'SELECT card_id, external_id FROM transactions '
        'WHERE external_id IS NOT NULL AND card_id IN (${_marks(part.length)})',
        part,
      );
      for (final r in rows) {
        result.add('${r['card_id']}|${r['external_id']}');
      }
    }
    if (ids.contains(null)) {
      final rows = await _db.rawQuery(
        'SELECT external_id FROM transactions WHERE external_id IS NOT NULL AND card_id IS NULL',
      );
      for (final r in rows) {
        result.add('cash|${r['external_id']}');
      }
    }
    return result;
  }

  /// hash -> how many saved rows have it.
  Future<Map<String, int>> hashCounts(Iterable<String> hashes) async {
    final list = hashes.toSet().toList();
    final result = <String, int>{};
    for (var i = 0; i < list.length; i += _chunk) {
      final part = list.sublist(i, math.min(i + _chunk, list.length));
      final rows = await _db.rawQuery(
        'SELECT dedup_hash AS h, COUNT(*) AS c FROM transactions '
        'WHERE dedup_hash IN (${_marks(part.length)}) GROUP BY dedup_hash',
        part,
      );
      for (final r in rows) {
        result[r['h'] as String] = r['c'] as int;
      }
    }
    return result;
  }

  /// Sets category on every transaction currently in [fromCategoryId].
  Future<void> reassignCategory(int fromCategoryId, int toCategoryId) async {
    await _db.update(
      'transactions',
      {'category_id': toCategoryId},
      where: 'category_id = ?',
      whereArgs: [fromCategoryId],
    );
  }

  Future<DateTime?> earliestDate() async {
    final r = await _db.rawQuery('SELECT MIN(date) AS d FROM transactions');
    final v = r.first['d'] as int?;
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  static String _marks(int n) => List.filled(n, '?').join(',');

  static String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
