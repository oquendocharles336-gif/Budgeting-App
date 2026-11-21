import 'package:path/path.dart' as p;

import '../security/password_crypto.dart';
import 'backup_crypto.dart';
import 'backup_service.dart';
import 'photo_service.dart';

export 'backup_service.dart' show BackupData, BackupException, RestoreMode;

/// What a backup file holds, shown before restoring.
class BackupSummary {
  const BackupSummary(this.data);
  final BackupData data;

  int get transactions => data.count('transactions');
  int get orders => data.count('orders');
  int get products => data.count('products');
  int get inventory => data.count('inventory_items');
  int get photos => data.photos.length;
}

/// One backup file = the whole database + every photo, encrypted with a
/// password the user picks (PBKDF2-HMAC-SHA256, 600,000 rounds ->
/// AES-256-GCM; see [BackupCrypto]).
///
/// Restore order, so nothing is ever half-restored:
///  1. decrypt (wrong password = stop) and check the contents;
///  2. encrypt the photos into a temporary folder with this phone's key;
///  3. replace or merge the database in one SQLite transaction;
///  4. only then move the photos into place (or delete the temporary
///     folder if step 3 failed).
class BackupBundleService {
  BackupBundleService({required this._backup, required this._photos});

  final BackupService _backup;
  final PhotoService _photos;

  /// The encrypted backup file's text.
  Future<String> export(String password) async {
    final tables = await _backup.exportTables();
    final paths = <String>[
      for (final t in ['inventory_items', 'products'])
        for (final row in tables[t] ?? const <Map<String, Object?>>[])
          if (row['photo_path'] is String) row['photo_path'] as String,
    ];
    final photos = await _photos.exportForBackup(paths);
    return BackupCrypto.encrypt(BackupService.encode(tables, photos: photos), password);
  }

  /// Opens and checks a backup without changing anything. Throws
  /// [WrongSecretException] for a wrong password and [BackupException]
  /// for a damaged or unsupported file. [password] may be null only for an
  /// old unencrypted backup.
  Future<BackupData> open(String text, String? password) async {
    String json = text;
    if (BackupCrypto.isEncrypted(text)) {
      if (password == null) throw const WrongSecretException('This backup needs its password');
      json = await BackupCrypto.decrypt(text, password);
    }
    return BackupService.parse(json);
  }

  Future<void> restore(BackupData data, {required RestoreMode mode}) async {
    final Map<String, String> staged;
    try {
      staged = await _photos.stageForRestore(data.photos);
    } on FormatException catch (e) {
      throw BackupException(e.message);
    }
    final finals = await _photos.finalPaths(staged);
    try {
      await _backup.restore(data, mode: mode, photoPath: (old) => old == null ? null : finals[p.basename(old)]);
    } catch (_) {
      await _photos.discardRestore();
      rethrow;
    }
    await _photos.commitRestore(staged);
    // Replace: photos of the old data are no longer referenced.
    if (mode == RestoreMode.replace) await _photos.cleanUp();
  }
}
