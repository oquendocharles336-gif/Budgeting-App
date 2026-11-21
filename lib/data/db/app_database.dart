import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// Opens the single on-device SQLite database.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const fileName = 'pitaka.db';

  static Future<AppDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), fileName);
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

  Future<void> close() => db.close();
}
