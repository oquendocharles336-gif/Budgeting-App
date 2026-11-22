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

  /// "Check for updates" switch ('0' = off; on by default).
  static const updateCheckEnabled = 'update_check_enabled';
  static const updateLastCheck = 'update_last_check';

  /// Build number the user chose to skip (before v1.2: read for upgrades).
  static const updateSkippedBuild = 'update_skipped_build';

  /// Version name ("1.2.0") the user chose to skip.
  static const updateSkippedVersion = 'update_skipped_version';

  /// Last build whose "What's new" was shown (before v1.2: read once to
  /// carry it over to [whatsNewSeenVersion]).
  static const whatsNewSeenBuild = 'whats_new_seen_build';

  /// Last app version ("1.2.0") the user has seen "What's new" for (or
  /// that was installed fresh). "What's new" shows only for a higher one.
  static const whatsNewSeenVersion = 'whats_new_seen_version';

  /// Business Mode switch ('1' = on): shows the Business tab in the bottom
  /// bar. Off by default.
  static const businessMode = 'business_mode';

  /// "Not now" on Home's "Allow" card: hidden until this time (ms).
  static const phoneAccessSnoozedUntil = 'phone_access_snoozed_until';

  /// Keys that are device-specific and never exported in backups.
  static const privateKeys = {
    pinHash,
    pinSalt,
    biometricEnabled,
    photoDraft,
    photosEncrypted,
    updateLastCheck,
    updateSkippedBuild,
    updateSkippedVersion,
    whatsNewSeenBuild,
    whatsNewSeenVersion,
    businessMode,
    phoneAccessSnoozedUntil,
  };

  /// Leftovers of the old PIN lock (before the password + encryption
  /// update). Only these are removed when the app unlocks. The other
  /// [privateKeys] must survive an unlock: they hold "What's new" seen,
  /// the last update check, the camera photo draft, and so on.
  static const legacyLockKeys = {pinHash, pinSalt, biometricEnabled};

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
