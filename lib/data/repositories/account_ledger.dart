import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/transaction_entry.dart';

/// Keeps account balances in step with transactions.
///
/// Accounts are the rows of `cards` (bank cards, e-wallets, ...) plus Cash,
/// which has no row: its balance lives in `settings` under [cashKey]. A
/// `null` account id always means Cash, as everywhere else in the app.
///
/// Every method takes the [DatabaseExecutor] of the caller's SQLite
/// transaction, so a balance change and the transaction row it belongs to
/// are written together or not at all.
class AccountLedger {
  AccountLedger._();

  static const cashKey = 'cash_balance';

  /// How [tx] moves money, as (account id, delta) pairs. Expenses take money
  /// out of the account, income puts it in, a transfer does both (a
  /// transfer into business capital only takes it out).
  static List<(int?, int)> effects(TransactionEntry tx) => switch (tx.kind) {
        TransactionKind.expense => [(tx.cardId, -tx.amount)],
        TransactionKind.income => [(tx.cardId, tx.amount)],
        // Into business capital: it leaves the personal account and doesn't
        // land in another one (toCardId null must not mean Cash here).
        TransactionKind.transfer when tx.toCapital => [(tx.cardId, -tx.amount)],
        // Out of business capital: only the personal destination changes.
        TransactionKind.transfer when tx.fromCapital => [(tx.toCardId, tx.amount)],
        TransactionKind.transfer => [(tx.cardId, -tx.amount), (tx.toCardId, tx.amount)],
      };

  /// Applies [tx] to the balances ([sign] = 1), or undoes it ([sign] = -1).
  /// Does nothing for rows that never touched a balance.
  static Future<void> apply(DatabaseExecutor db, TransactionEntry tx, {int sign = 1}) async {
    if (!tx.affectsBalance) return;
    for (final (account, delta) in effects(tx)) {
      await adjust(db, account, delta * sign);
    }
  }

  /// Adds [delta] centavos to one account (null = Cash).
  static Future<void> adjust(DatabaseExecutor db, int? accountId, int delta) async {
    if (delta == 0) return;
    if (accountId != null) {
      await db.rawUpdate('UPDATE cards SET balance = balance + ? WHERE id = ?', [delta, accountId]);
      return;
    }
    // No UPSERT on Android 7's SQLite: update, then insert if nothing changed.
    final changed = await db.rawUpdate(
      'UPDATE settings SET value = CAST(CAST(value AS INTEGER) + ? AS TEXT) WHERE key = ?',
      [delta, cashKey],
    );
    if (changed == 0) {
      await db.insert('settings', {'key': cashKey, 'value': '$delta'});
    }
  }

  /// Current balance of one account (null = Cash).
  static Future<int> balanceOf(DatabaseExecutor db, int? accountId) async {
    if (accountId == null) return cashBalance(db);
    final rows = await db.query('cards', columns: ['balance'], where: 'id = ?', whereArgs: [accountId], limit: 1);
    return rows.isEmpty ? 0 : (rows.first['balance'] as int? ?? 0);
  }

  static Future<int> cashBalance(DatabaseExecutor db) async {
    final rows = await db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: [cashKey], limit: 1);
    return rows.isEmpty ? 0 : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
  }

  /// Sets an account's balance to [value] (the user typed the real amount).
  static Future<void> setBalance(DatabaseExecutor db, int? accountId, int value) async {
    if (accountId != null) {
      await db.update('cards', {'balance': value}, where: 'id = ?', whereArgs: [accountId]);
      return;
    }
    await db.insert('settings', {'key': cashKey, 'value': '$value'}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
