import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/payment_card.dart';
import '../models/transaction_entry.dart';
import 'account_ledger.dart';
import 'linked_records.dart';

class CardRepository {
  CardRepository(this._db);
  final Database _db;

  Future<List<PaymentCard>> all({bool includeArchived = false}) async {
    final rows = await _db.query(
      'cards',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'archived, nickname COLLATE NOCASE',
    );
    return rows.map(PaymentCard.fromMap).toList();
  }

  Future<PaymentCard?> byId(int id) async {
    final rows = await _db.query('cards', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PaymentCard.fromMap(rows.first);
  }

  Future<int> insert(PaymentCard card) => _db.insert('cards', card.toMap()..remove('id'));

  /// Saves name, type, color, etc. The balance is left alone: it only
  /// changes through transactions or [setBalance], so a card object loaded
  /// a moment ago can't overwrite a newer balance.
  Future<void> update(PaymentCard card) async {
    await _db.update('cards', card.toMap()..remove('balance'), where: 'id = ?', whereArgs: [card.id]);
  }

  /// The user typed the account's real current amount ([accountId] null = Cash).
  Future<void> setBalance(int? accountId, int balance) => AccountLedger.setBalance(_db, accountId, balance);

  Future<int> cashBalance() => AccountLedger.cashBalance(_db);

  Future<int> balanceOf(int? accountId) => AccountLedger.balanceOf(_db, accountId);

  Future<int> transactionCount(int cardId) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions WHERE card_id = ? OR to_card_id = ?',
      [cardId, cardId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Deletes the card. Its transactions must be deleted too, because a card
  /// transaction can't silently turn into a cash one.
  Future<void> delete(int cardId) async {
    await _db.transaction((txn) async {
      // A transfer between this card and another account also moved the
      // other account's balance; give that back before the row disappears.
      final rows = await txn.query(
        'transactions',
        where: '(card_id = ? OR to_card_id = ?) AND affects_balance = 1',
        whereArgs: [cardId, cardId],
      );
      for (final r in rows) {
        await AccountLedger.apply(txn, TransactionEntry.fromMap(r), sign: -1);
      }
      final ids = await txn.query('transactions', columns: ['id'], where: 'card_id = ? OR to_card_id = ?', whereArgs: [cardId, cardId]);
      await LinkedRecords.beforeTransactionsDeleted(txn, [for (final r in ids) r['id'] as int]);
      await txn.delete('transactions', where: 'card_id = ? OR to_card_id = ?', whereArgs: [cardId, cardId]);
      await txn.delete('cards', where: 'id = ?', whereArgs: [cardId]);
    });
  }
}
