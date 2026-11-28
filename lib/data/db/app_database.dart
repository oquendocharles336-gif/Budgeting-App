import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migrations.dart';

/// Opens the single on-device SQLite database, encrypted with SQLCipher.
///
/// The passphrase comes from the user's data key (see `Vault`); without it
/// the file is unreadable.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  /// Encrypted database (since login was added).
  static const fileName = 'pitaka_secure.db';

  /// Unencrypted database used by earlier versions of the app.
  static const legacyFileName = 'pitaka.db';

  static Future<String> directory() => getDatabasesPath();

  static Future<AppDatabase> open({required String passphrase, String? path}) async {
    final dbPath = path ?? p.join(await directory(), fileName);
    final db = await openDatabase(
      dbPath,
      password: passphrase,
      version: Migrations.latestVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) => Migrations.run(db, 0, version),
      onUpgrade: (db, oldVersion, newVersion) => Migrations.run(db, oldVersion, newVersion),
    );
    return AppDatabase._(db);
  }

  static Future<AppDatabase> openPlain({String? path}) async {
    final dbPath = path ?? p.join(await directory(), legacyFileName);
    final db = await openDatabase(
      dbPath,
      version: Migrations.latestVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) => Migrations.run(db, 0, version),
      onUpgrade: (db, oldVersion, newVersion) => Migrations.run(db, oldVersion, newVersion),
    );
    return AppDatabase._(db);
  }

  static Future<bool> legacyExists() async => File(p.join(await directory(), legacyFileName)).exists();

  static Future<bool> encryptedExists() async => File(p.join(await directory(), fileName)).exists();

  /// Deletes an encrypted file whose key was never saved (an interrupted
  /// first-time set-up). Its contents can't be opened by anyone anyway.
  static Future<void> deleteOrphanedEncrypted() async => deleteDatabase(p.join(await directory(), fileName));

  /// Copies the old unencrypted database into a new encrypted one
  /// (SQLCipher's `sqlcipher_export`). The old file is left in place;
  /// call [deleteLegacy] once the vault for the new key has been saved.
  static Future<void> encryptLegacy({required String passphrase}) async {
    final dir = await directory();
    final plainPath = p.join(dir, legacyFileName);
    final securePath = p.join(dir, fileName);
    await deleteDatabase(securePath);
    final plain = await openDatabase(plainPath); // no password = plain SQLite
    try {
      final version = (await plain.rawQuery('PRAGMA user_version')).first.values.first as int? ?? 0;
      await plain.execute('ATTACH DATABASE ? AS encrypted KEY ?', [securePath, passphrase]);
      await plain.rawQuery("SELECT sqlcipher_export('encrypted')");
      // sqlcipher_export doesn't copy the schema version; migrations need it.
      await plain.execute('PRAGMA encrypted.user_version = $version');
      await plain.execute('DETACH DATABASE encrypted');
    } finally {
      await plain.close();
    }
  }

  /// Removes the old unencrypted file. Note: flash storage may keep old
  /// blocks until they're reused; that is outside the app's control.
  static Future<void> deleteLegacy() async => deleteDatabase(p.join(await directory(), legacyFileName));

  Future<void> close() => db.close();
}
