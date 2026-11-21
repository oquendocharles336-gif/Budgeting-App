import 'package:sqflite_sqlcipher/sqflite.dart';

/// Key/value app settings stored in the `settings` table.
class SettingsRepository {
  SettingsRepository(this._db);
  final Database _db;

  static const currency = 'currency';
  static const themeMode = 'theme_mode';
  static const accentColor = 'accent_color';
  static const termsAccepted = 'terms_accepted_version';
  static const pinHash = 'pin_hash';
  static const pinSalt = 'pin_salt';
  static const biometricEnabled = 'biometric_enabled';
  static const smsEnabled = 'sms_enabled';
  static const cardOnboardingSeen = 'card_onboarding_seen';

  /// Form being filled in when the camera opened (restored if Android
  /// closes the app meanwhile).
  static const photoDraft = 'photo_draft';

  /// Set once every old plain photo has been encrypted.
  static const photosEncrypted = 'photos_encrypted_v1';

  /// Keys that are device-specific and never exported in backups.
  static const privateKeys = {pinHash, pinSalt, biometricEnabled, photoDraft, photosEncrypted};

  static String budgetAlertKey(String month) => 'budget_alerts_$month';

  Future<Map<String, String>> all() async {
    final rows = await _db.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''};
  }

  Future<String?> get(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
