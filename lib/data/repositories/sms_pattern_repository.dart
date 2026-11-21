import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db/default_data.dart';
import '../models/sms_pattern.dart';

class SmsPatternRepository {
  SmsPatternRepository(this._db);
  final Database _db;

  Future<List<SmsPattern>> all() async {
    final rows = await _db.query('sms_patterns', orderBy: 'id');
    return rows.map(SmsPattern.fromMap).toList();
  }

  Future<int> insert(SmsPattern p) => _db.insert('sms_patterns', p.toMap()..remove('id'));

  Future<void> update(SmsPattern p) async {
    await _db.update('sms_patterns', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  Future<void> delete(int id) async {
    await _db.delete('sms_patterns', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetToDefaults() async {
    await _db.transaction((txn) async {
      await txn.delete('sms_patterns');
      for (final p in DefaultData.smsPatterns) {
        await txn.insert('sms_patterns', p.toMap());
      }
    });
  }
}
