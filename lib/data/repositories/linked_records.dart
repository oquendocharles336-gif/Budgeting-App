import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/transaction_entry.dart';
import 'account_ledger.dart';

/// Rows in other tables that point at a transaction, kept consistent when
/// transactions are deleted. Runs inside the caller's SQLite transaction.
///
///  * A transfer's "Fees" expense is deleted with it (and its balance
///    change undone), so a fee is never left behind for a transfer that
///    no longer exists.
///  * The business capital entry a capital transfer recorded is removed,
///    so the capital balance and the personal balances stay in step.
///  * A Pay Later item whose expense is deleted is unlinked (it stays
///    "Paid"; the user removed the expense on purpose).
///  * Orders whose sales income is deleted can be added to the budget again.
class LinkedRecords {
  LinkedRecords._();

  static const _chunk = 400;

  static Future<void> beforeTransactionsDeleted(DatabaseExecutor db, List<int> ids) async {
    if (ids.isEmpty) return;
    final deleting = ids.toSet();
    for (var i = 0; i < ids.length; i += _chunk) {
      final part = ids.sublist(i, math.min(i + _chunk, ids.length));
      final marks = List.filled(part.length, '?').join(',');
      final fees = await db.query('transactions', where: 'fee_of_id IN ($marks)', whereArgs: part);
      for (final row in fees) {
        final fee = TransactionEntry.fromMap(row);
        if (deleting.contains(fee.id)) continue; // Already being deleted (and undone) by the caller.
        await AccountLedger.apply(db, fee, sign: -1);
        await db.delete('transactions', where: 'id = ?', whereArgs: [fee.id]);
      }
      await db.delete('capital_entries', where: 'transaction_id IN ($marks)', whereArgs: part);
      await db.update('pay_later', {'expense_tx_id': null}, where: 'expense_tx_id IN ($marks)', whereArgs: part);
      await db.update(
        'orders',
        {'budget_tx_id': null, 'added_to_budget_at': null},
        where: 'budget_tx_id IN ($marks)',
        whereArgs: part,
      );
    }
  }
}
