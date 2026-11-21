import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/transaction_entry.dart';
import 'account_ledger.dart';
import 'linked_records.dart';
import 'op_guard.dart';

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
      // A transfer into business capital has no destination account, so a
      // NULL to_card_id there doesn't mean Cash.
      // Transfers to/from business capital have no personal account on that
      // side, so a NULL there doesn't mean Cash.
      where.add("((card_id IS NULL AND from_capital = 0) OR (kind = 'transfer' AND to_card_id IS NULL AND to_capital = 0))");
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

  /// Saves a transfer and, when there is one, its fee as a separate
  /// "Fees" expense (linked by `fee_of_id`), in one SQLite transaction.
  /// [afterInsert] runs in the same transaction with the transfer's id
  /// (used to record business capital; throwing there undoes everything).
  /// With an [opKey], a retry or double tap returns the first transfer's id
  /// and writes nothing, so a transfer is never saved twice.
  Future<int> insertTransfer(
    TransactionEntry transfer, {
    TransactionEntry? fee,
    Future<void> Function(DatabaseExecutor txn, int transferId)? afterInsert,
    String? opKey,
  }) =>
      _db.transaction((txn) => OpGuard.once(txn, opKey, () async {
        final id = await txn.insert('transactions', transfer.toMap()..remove('id'));
        await AccountLedger.apply(txn, transfer);
        if (fee != null) {
          final linked = fee.copyWith(feeOfId: () => id);
          await txn.insert('transactions', linked.toMap()..remove('id'));
          await AccountLedger.apply(txn, linked);
        }
        if (afterInsert != null) await afterInsert(txn, id);
        return id;
      }));

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
        // Whether a row moves balances, and whether a transfer went into
        // business capital, are fixed when it is created.
        final next = tx.copyWith(affectsBalance: old.affectsBalance, toCapital: old.toCapital, fromCapital: old.fromCapital);
        await txn.update('transactions', next.toMap(), where: 'id = ?', whereArgs: [tx.id]);
        await AccountLedger.apply(txn, next);
        // A transfer's fee is paid from the same account: follow a change.
        if (old.isTransfer && next.isTransfer && old.cardId != next.cardId) {
          final fees = await txn.query('transactions', where: 'fee_of_id = ?', whereArgs: [tx.id]);
          for (final row in fees) {
            final fee = TransactionEntry.fromMap(row);
            await AccountLedger.apply(txn, fee, sign: -1);
            final moved = fee.copyWith(cardId: () => next.cardId, updatedAt: DateTime.now());
            await txn.update('transactions', moved.toMap(), where: 'id = ?', whereArgs: [fee.id]);
            await AccountLedger.apply(txn, moved);
          }
        }
      });

  /// Deletes the row and gives its money back to (or takes it from) the account.
  Future<void> delete(int id) => _db.transaction((txn) async {
        final old = await _byId(txn, id);
        if (old == null) return;
        await LinkedRecords.beforeTransactionsDeleted(txn, [id]);
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

  /// Fee expenses saved for [transferId] (normally zero or one).
  Future<List<TransactionEntry>> feesOf(int transferId) async {
    final rows = await _db.query('transactions', where: 'fee_of_id = ?', whereArgs: [transferId], orderBy: 'id');
    return rows.map(TransactionEntry.fromMap).toList();
  }

  /// Transactions filed under the "Loan" category (or any category the user
  /// named "Loan"): unpaid first, newest first. The payment expenses made
  /// when a loan was marked paid are not loans themselves, so they're left out.
  Future<List<TransactionEntry>> loans() async {
    final rows = await _db.rawQuery('''
      SELECT t.* FROM transactions t
      JOIN categories c ON c.id = t.category_id
      WHERE (c.role = 'loanRecord' OR c.name = 'Loan' COLLATE NOCASE)
        AND t.loan_payment_of_id IS NULL
      ORDER BY t.loan_paid_at IS NOT NULL, t.date DESC, t.id DESC
    ''');
    return rows.map(TransactionEntry.fromMap).toList();
  }

  /// Every loan payment expense, by the loan it pays.
  Future<Map<int, TransactionEntry>> loanPayments() async {
    final rows = await _db.query('transactions', where: 'loan_payment_of_id IS NOT NULL', orderBy: 'id');
    return {for (final r in rows) r['loan_payment_of_id'] as int: TransactionEntry.fromMap(r)};
  }

  /// The payment expense saved when [loanId] was marked paid, if any.
  Future<TransactionEntry?> loanPaymentOf(int loanId) async {
    final rows = await _db.query('transactions', where: 'loan_payment_of_id = ?', whereArgs: [loanId], orderBy: 'id', limit: 1);
    return rows.isEmpty ? null : TransactionEntry.fromMap(rows.first);
  }

  /// Marks a loan paid with [method], and saves [payment] (an expense on
  /// the paying account) linked to it, in one SQLite transaction: the
  /// account goes down and the payment counts in that month's budget.
  /// Marking a loan that is already paid does nothing (double taps are safe).
  /// Returns the payment's id, or null when nothing was written.
  Future<int?> markLoanPaid(int loanId, {required LoanPayMethod method, required TransactionEntry payment}) =>
      _db.transaction((txn) async {
        final loan = await _byId(txn, loanId);
        if (loan == null) throw StateError('This loan no longer exists');
        if (loan.isLoanPaid) return null;
        final linked = payment.copyWith(loanPaymentOfId: () => loanId);
        final id = await txn.insert('transactions', linked.toMap()..remove('id'));
        await AccountLedger.apply(txn, linked);
        await txn.update(
          'transactions',
          {
            'loan_paid_at': payment.date.millisecondsSinceEpoch,
            'loan_paid_method': method.dbValue,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [loanId],
        );
        return id;
      });

  /// Marks a loan unpaid: its payment expense is deleted and the money goes
  /// back to the account it was paid from, atomically.
  Future<void> markLoanUnpaid(int loanId) => _db.transaction((txn) async {
        final rows = await txn.query('transactions', where: 'loan_payment_of_id = ?', whereArgs: [loanId]);
        for (final row in rows) {
          final payment = TransactionEntry.fromMap(row);
          await LinkedRecords.beforeTransactionsDeleted(txn, [payment.id!]);
          await AccountLedger.apply(txn, payment, sign: -1);
          await txn.delete('transactions', where: 'id = ?', whereArgs: [payment.id]);
        }
        await txn.update(
          'transactions',
          {'loan_paid_at': null, 'loan_paid_method': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [loanId],
        );
      });

  /// The earliest day with spending to chart (Insights shows expenses only).
  Future<DateTime?> earliestExpenseDate() async {
    final r = await _db.rawQuery(
      "SELECT MIN(date) AS d FROM transactions WHERE kind = 'expense' AND amount > 0 AND date > 0",
    );
    final v = r.first['d'] as int?;
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
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
