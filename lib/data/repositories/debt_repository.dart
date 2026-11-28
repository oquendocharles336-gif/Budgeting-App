import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/debt.dart';
import '../models/transaction_entry.dart';

class DebtRepository {
  DebtRepository(this._db);
  final Database _db;

  /// Open first (overdue, then soonest next monthly due date), then settled.
  Future<List<DebtStatus>> allStatuses({DebtDirection? direction}) async {
    final where = direction == null ? '' : "WHERE d.direction = '${direction.dbValue}'";
    final rows = await _db.rawQuery('''
      SELECT d.*, IFNULL(p.total, 0) AS payments_total, IFNULL(p.cnt, 0) AS payments_count
      FROM debts d
      LEFT JOIN (
        SELECT debt_id, SUM(amount) AS total, COUNT(*) AS cnt FROM debt_payments GROUP BY debt_id
      ) p ON p.debt_id = d.id
      $where
      ORDER BY d.is_paid, d.creditor COLLATE NOCASE
    ''');
    final list = [
      for (final r in rows)
        DebtStatus(
          debt: Debt.fromMap(r),
          paymentsTotal: (r['payments_total'] as int?) ?? 0,
          paymentsCount: (r['payments_count'] as int?) ?? 0,
        ),
    ];
    return sortStatuses(list, DateTime.now());
  }

  /// Open before settled; among open ones, the earliest overdue / next due
  /// date first, then the ones with no due day. Stable for equal keys.
  static List<DebtStatus> sortStatuses(List<DebtStatus> list, DateTime now) {
    DateTime? key(DebtStatus s) => s.overdueSince(now) ?? s.nextDue(now);
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final sa = a.$2.isSettled ? 1 : 0, sb = b.$2.isSettled ? 1 : 0;
        if (sa != sb) return sa - sb;
        final ka = key(a.$2), kb = key(b.$2);
        if (ka != null && kb != null && ka != kb) return ka.compareTo(kb);
        if ((ka == null) != (kb == null)) return ka == null ? 1 : -1;
        return a.$1 - b.$1;
      });
    return [for (final e in indexed) e.$2];
  }

  /// How many debts are still open (not marked paid and something left to
  /// pay) for borrowed debts and lent loans in the unified table.
  Future<({int debts, int loans})> openCounts() async {
    final r = await _db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM debts d
           LEFT JOIN (SELECT debt_id, SUM(amount) AS total FROM debt_payments GROUP BY debt_id) p
             ON p.debt_id = d.id
           WHERE d.is_paid = 0 AND d.direction = 'borrowed'
             AND d.total_amount - d.initial_paid - IFNULL(p.total, 0) > 0) AS open_debts,
        (SELECT COUNT(*) FROM debts d
           LEFT JOIN (SELECT debt_id, SUM(amount) AS total FROM debt_payments GROUP BY debt_id) p
             ON p.debt_id = d.id
           WHERE d.is_paid = 0 AND d.direction = 'lent'
             AND d.total_amount - d.initial_paid - IFNULL(p.total, 0) > 0) AS open_loans
    ''');
    final row = r.first;
    return (
      debts: (row['open_debts'] as num?)?.toInt() ?? 0,
      loans: (row['open_loans'] as num?)?.toInt() ?? 0,
    );
  }

  Future<DebtStatus?> statusById(int id) async {
    final all = await allStatuses();
    for (final s in all) {
      if (s.debt.id == id) return s;
    }
    return null;
  }

  /// Saves a debt and, for a new debt, the expense/transaction it creates,
  /// in one SQLite transaction.
  Future<int> insert(Debt d, {TransactionEntry Function(int debtId)? linkedExpense}) =>
      _db.transaction((txn) async {
        final id = await txn.insert('debts', d.toMap()..remove('id'));
        if (linkedExpense != null) {
          await txn.insert('transactions', linkedExpense(id).toMap()..remove('id'));
        }
        return id;
      });

  /// Saves the edit and keeps the linked expense/transaction in step.
  Future<void> update(Debt d, {TransactionEntry Function(TransactionEntry? current)? linkedExpense}) =>
      _db.transaction((txn) async {
        await txn.update('debts', d.toMap(), where: 'id = ?', whereArgs: [d.id]);
        if (linkedExpense == null) return;
        final current = await _linked(txn, d.id!);
        final next = linkedExpense(current);
        if (current == null) {
          await txn.insert('transactions', next.toMap()..remove('id'));
        } else {
          await txn.update('transactions', next.toMap(), where: 'id = ?', whereArgs: [current.id]);
        }
      });

  /// The expense a new debt created, if it still exists.
  Future<TransactionEntry?> linkedExpense(int debtId) => _linked(_db, debtId);

  static Future<TransactionEntry?> _linked(DatabaseExecutor db, int debtId) async {
    final rows = await db.query('transactions', where: 'debt_id = ?', whereArgs: [debtId], orderBy: 'id', limit: 1);
    return rows.isEmpty ? null : TransactionEntry.fromMap(rows.first);
  }

  /// Deletes the debt (payments go with it).
  Future<void> delete(int id, {bool removeLinkedExpense = false}) => _db.transaction((txn) async {
        if (removeLinkedExpense) {
          await txn.delete('transactions', where: 'debt_id = ?', whereArgs: [id]);
        } else {
          await txn.update('transactions', {'debt_id': null}, where: 'debt_id = ?', whereArgs: [id]);
        }
        await txn.delete('debts', where: 'id = ?', whereArgs: [id]);
      });

  Future<List<DebtPayment>> payments(int debtId) async {
    final rows = await _db.query(
      'debt_payments',
      where: 'debt_id = ?',
      whereArgs: [debtId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(DebtPayment.fromMap).toList();
  }

  Future<int> addPayment(DebtPayment p) => _db.insert('debt_payments', p.toMap()..remove('id'));

  Future<void> deletePayment(int id) async {
    await _db.delete('debt_payments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setPaid(int debtId, bool paid) async {
    await _db.update(
      'debts',
      {'is_paid': paid ? 1 : 0, 'paid_at': paid ? DateTime.now().millisecondsSinceEpoch : null},
      where: 'id = ?',
      whereArgs: [debtId],
    );
  }
}
