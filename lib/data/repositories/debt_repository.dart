import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/debt.dart';
import '../models/transaction_entry.dart';

class DebtRepository {
  DebtRepository(this._db);
  final Database _db;

  /// Unpaid first (soonest due first), then paid.
  Future<List<DebtStatus>> allStatuses() async {
    final rows = await _db.rawQuery('''
      SELECT d.*, IFNULL(p.total, 0) AS payments_total
      FROM debts d
      LEFT JOIN (
        SELECT debt_id, SUM(amount) AS total FROM debt_payments GROUP BY debt_id
      ) p ON p.debt_id = d.id
      ORDER BY d.is_paid, d.due_date IS NULL, d.due_date, d.creditor COLLATE NOCASE
    ''');
    return [
      for (final r in rows)
        DebtStatus(debt: Debt.fromMap(r), paymentsTotal: (r['payments_total'] as int?) ?? 0),
    ];
  }

  /// How many debts are still open (not marked paid and something left to
  /// pay) and how many "Loan" transactions are not marked paid, in one
  /// query. Same rules as [DebtStatus.isSettled] and
  /// `TransactionRepository.loans()` (payment expenses are not loans).
  Future<({int debts, int loans})> openCounts() async {
    final r = await _db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM debts d
           LEFT JOIN (SELECT debt_id, SUM(amount) AS total FROM debt_payments GROUP BY debt_id) p
             ON p.debt_id = d.id
           WHERE d.is_paid = 0
             AND d.total_amount - d.initial_paid - IFNULL(p.total, 0) > 0) AS open_debts,
        (SELECT COUNT(*) FROM transactions t
           JOIN categories c ON c.id = t.category_id
           WHERE (c.role = 'loanRecord' OR c.name = 'Loan' COLLATE NOCASE)
             AND t.loan_payment_of_id IS NULL
             AND t.loan_paid_at IS NULL) AS open_loans
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

  /// Saves a debt and, for a new debt, the expense it creates, in one
  /// SQLite transaction. [linkedExpense] gets the new debt's id.
  Future<int> insert(Debt d, {TransactionEntry Function(int debtId)? linkedExpense}) =>
      _db.transaction((txn) async {
        final id = await txn.insert('debts', d.toMap()..remove('id'));
        if (linkedExpense != null) {
          await txn.insert('transactions', linkedExpense(id).toMap()..remove('id'));
        }
        return id;
      });

  /// Saves the edit and keeps the linked expense in step: [linkedExpense]
  /// receives the current one (or null) and returns what it should be.
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

  /// Deletes the debt (payments go with it). The linked expense is removed
  /// too if [removeLinkedExpense]; otherwise it stays and is just unlinked.
  /// Linked expenses never move account balances, so nothing to undo there.
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
