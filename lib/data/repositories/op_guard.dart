import 'package:sqflite_sqlcipher/sqflite.dart';

/// "Do this once" for user actions (save, pay, transfer, restock).
///
/// The UI makes one key per action (see `newOpKey`) and keeps it for
/// retries. A write runs [OpGuard.once] inside its SQLite transaction: the
/// first run records the key with its result; a double tap or a "Try
/// again" after a write that actually succeeded finds the key and returns
/// the first result without writing anything.
class OpGuard {
  OpGuard._();

  static Future<int> once(
    DatabaseExecutor txn,
    String? key,
    Future<int> Function() write,
  ) async {
    if (key == null) return write();
    final rows = await txn.query('op_keys', columns: ['result'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isNotEmpty) return (rows.first['result'] as int?) ?? 0;
    final result = await write();
    await txn.insert('op_keys', {
      'key': key,
      'result': result,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return result;
  }

  /// Whether [key] already ran (for writes with no result to return).
  static Future<bool> done(DatabaseExecutor db, String? key) async {
    if (key == null) return false;
    final rows = await db.query('op_keys', columns: ['key'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isNotEmpty;
  }

  /// Keys older than [age] are no longer needed (a retry comes within
  /// minutes). Called at start-up to keep the table small.
  static Future<void> prune(DatabaseExecutor db, {Duration age = const Duration(days: 30)}) async {
    final cutoff = DateTime.now().subtract(age).millisecondsSinceEpoch;
    await db.delete('op_keys', where: 'created_at < ?', whereArgs: [cutoff]);
  }
}
