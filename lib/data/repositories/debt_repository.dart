import 'package:sqflite/sqflite.dart';

import '../models/debt.dart';

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

  Future<DebtStatus?> statusById(int id) async {
    final all = await allStatuses();
    for (final s in all) {
      if (s.debt.id == id) return s;
    }
    return null;
  }

  Future<int> insert(Debt d) => _db.insert('debts', d.toMap()..remove('id'));

  Future<void> update(Debt d) async {
    await _db.update('debts', d.toMap(), where: 'id = ?', whereArgs: [d.id]);
  }

  Future<void> delete(int id) async {
    await _db.delete('debts', where: 'id = ?', whereArgs: [id]);
  }

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
