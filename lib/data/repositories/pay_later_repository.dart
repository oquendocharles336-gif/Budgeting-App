import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/pay_later.dart';
import '../models/transaction_entry.dart';
import 'account_ledger.dart';
import 'op_guard.dart';

/// Result of [PayLaterRepository.markPaid].
typedef MarkPaidResult = ({int expenseId, bool alreadyPaid});

class PayLaterRepository {
  PayLaterRepository(this._db);
  final Database _db;

  /// Unpaid first (soonest due first), then paid (latest paid first).
  Future<List<PayLaterItem>> all() async {
    final rows = await _db.query(
      'pay_later',
      orderBy: "status = 'paid', CASE WHEN status = 'paid' THEN -IFNULL(paid_at, 0) ELSE due_date END, id",
    );
    return rows.map(PayLaterItem.fromMap).toList();
  }

  Future<PayLaterItem?> byId(int id) => _byId(_db, id);

  static Future<PayLaterItem?> _byId(DatabaseExecutor db, int id) async {
    final rows = await db.query('pay_later', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PayLaterItem.fromMap(rows.first);
  }

  /// With an [opKey], a retry returns the first insert's id (no duplicate).
  Future<int> insert(PayLaterItem p, {String? opKey}) => _db.transaction(
        (txn) => OpGuard.once(txn, opKey, () => txn.insert('pay_later', p.toMap()..remove('id'))),
      );

  /// Saves name, amount, dates and notes. Status and the linked expense
  /// only change through [markPaid] / [markUnpaid].
  Future<void> update(PayLaterItem p) async {
    final map = p.toMap()
      ..remove('status')
      ..remove('paid_at')
      ..remove('expense_tx_id');
    await _db.update('pay_later', map, where: 'id = ?', whereArgs: [p.id]);
  }

  /// Marks the item paid and creates its expense, in one SQLite
  /// transaction. The row is read again inside the transaction: if it is
  /// already paid (a double tap, two screens), nothing is created and the
  /// existing expense id is returned, so it is never counted twice.
  Future<MarkPaidResult> markPaid(
    int id, {
    required DateTime paidAt,
    required TransactionEntry Function(PayLaterItem item) expenseFor,
  }) =>
      _db.transaction((txn) async {
        final item = await _byId(txn, id);
        if (item == null) throw StateError('This Pay Later item no longer exists');
        if (item.isPaid) return (expenseId: item.expenseTxId ?? -1, alreadyPaid: true);
        final expense = expenseFor(item);
        final txId = await txn.insert('transactions', expense.toMap()..remove('id'));
        await AccountLedger.apply(txn, expense);
        // The WHERE keeps this a no-op if anything marked it paid meanwhile.
        final changed = await txn.update(
          'pay_later',
          {
            'status': PayLaterStatus.paid.name,
            'paid_at': paidAt.millisecondsSinceEpoch,
            'expense_tx_id': txId,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: "id = ? AND status = 'unpaid'",
          whereArgs: [id],
        );
        if (changed != 1) throw StateError('Pay Later item changed while saving');
        return (expenseId: txId, alreadyPaid: false);
      });

  /// Undo of "Paid": deletes the expense it created (giving the money back
  /// to the account) and sets it to unpaid again.
  Future<void> markUnpaid(int id) => _db.transaction((txn) async {
        final item = await _byId(txn, id);
        if (item == null || !item.isPaid) return;
        await _deleteExpense(txn, item.expenseTxId);
        await txn.update(
          'pay_later',
          {
            'status': PayLaterStatus.unpaid.name,
            'paid_at': null,
            'expense_tx_id': null,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      });

  /// Deletes the item. Its expense (if paid) stays unless [removeExpense].
  Future<void> delete(int id, {bool removeExpense = false}) => _db.transaction((txn) async {
        final item = await _byId(txn, id);
        if (item == null) return;
        if (removeExpense) await _deleteExpense(txn, item.expenseTxId);
        await txn.delete('pay_later', where: 'id = ?', whereArgs: [id]);
      });

  static Future<void> _deleteExpense(DatabaseExecutor txn, int? txId) async {
    if (txId == null) return;
    final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [txId], limit: 1);
    if (rows.isEmpty) return;
    await AccountLedger.apply(txn, TransactionEntry.fromMap(rows.first), sign: -1);
    await txn.delete('transactions', where: 'id = ?', whereArgs: [txId]);
  }
}
