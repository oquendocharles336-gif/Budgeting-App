import 'package:sqflite/sqflite.dart';

import '../models/payment_card.dart';

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

  Future<void> update(PaymentCard card) async {
    await _db.update('cards', card.toMap(), where: 'id = ?', whereArgs: [card.id]);
  }

  Future<int> transactionCount(int cardId) async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM transactions WHERE card_id = ?', [cardId]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// Deletes the card. Its transactions must be deleted too, because a card
  /// transaction can't silently turn into a cash one.
  Future<void> delete(int cardId) async {
    await _db.transaction((txn) async {
      await txn.delete('transactions', where: 'card_id = ?', whereArgs: [cardId]);
      await txn.delete('cards', where: 'id = ?', whereArgs: [cardId]);
    });
  }
}
