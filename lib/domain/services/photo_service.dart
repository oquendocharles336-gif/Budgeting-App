import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../data/repositories/business_repositories.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/photo_store.dart';
import '../security/photo_crypto.dart';
import 'app_lock_service.dart';
import 'photo_recovery.dart';

export '../../data/sources/photo_store.dart' show PhotoAccessDenied, PhotoSource;
export 'photo_recovery.dart' show PhotoDraft, RecoveredForm;

/// Progress of the one-time encryption of photos saved before v8.
class PhotoMigrationProgress {
  const PhotoMigrationProgress({required this.total, required this.done, required this.failed, required this.finished});
  final int total;
  final int done;
  final int failed;
  final bool finished;
}

/// Photos for inventory items and products: compress (picker) -> encrypt
/// (AES-256-GCM, key in the Android Keystore) -> save. Shown by decrypting
/// in memory only.
class PhotoService {
  PhotoService({
    required this._store,
    required this._crypto,
    required this._keys,
    required this._inventory,
    required this._products,
    required this._settings,
  });

  final PhotoStore _store;
  final PhotoCrypto _crypto;
  final PhotoKeyStore _keys;
  final InventoryRepository _inventory;
  final ProductRepository _products;
  final SettingsRepository _settings;

  /// Decoded photos kept in memory (never written back to disk).
  static const _cacheSize = 60;
  /// A map literal keeps insertion order, so the first key is the oldest.
  final _cache = <String, Uint8List>{};

  /// A recovered form waiting to be opened (see [recoverLost]).
  RecoveredForm? _pendingRecovery;

  // ---------------------------------------------------------------------------
  // Pick, save, show
  // ---------------------------------------------------------------------------

  /// Path of the new encrypted photo, or null if cancelled. Runs inside
  /// [LockGuard.run]: the camera / gallery is another app, and leaving
  /// Pitaka normally locks it. Throws [PhotoAccessDenied].
  Future<String?> pick(PhotoSource source) async {
    final working = await LockGuard.run(() => _store.pickWorkingCopy(source));
    if (working == null) return null;
    return importWorkingCopy(working);
  }

  /// Encrypts a plain picker file into the photo folder and deletes the plain file.
  Future<String> importWorkingCopy(String working) async {
    try {
      final plain = await _store.read(working);
      final path = await _store.writeEncrypted(await _crypto.encrypt(plain));
      _remember(path, plain);
      return path;
    } finally {
      await _store.deleteWorkingCopy(working);
    }
  }

  /// The photo's bytes for display. Old plain photos (before encryption
  /// finished) are read as they are. Throws if the file is missing or
  /// can't be decrypted.
  Future<Uint8List> read(String path) async {
    final hit = _cache.remove(path);
    if (hit != null) {
      _cache[path] = hit; // most recently used
      return hit;
    }
    final raw = await _store.read(path);
    final bytes = PhotoCrypto.isEncrypted(raw) ? await _crypto.decrypt(raw) : raw;
    _remember(path, bytes);
    return bytes;
  }

  void _remember(String path, Uint8List bytes) {
    _cache[path] = bytes;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<void> delete(String? path) async {
    if (path == null) return;
    _cache.remove(path);
    try {
      await _store.delete(path);
    } catch (_) {
      // A file that can't be deleted now is removed by [cleanUp].
    }
  }

  /// Deletes every photo file and the photo key ("Delete all my data").
  Future<void> deleteAll() async {
    _cache.clear();
    _pendingRecovery = null;
    await _store.deleteAll();
    await _keys.delete();
    _crypto.forgetKey();
    await _settings.remove(SettingsRepository.photoDraft);
    for (final key in SettingsRepository.paymentQrKeys) {
      await _settings.remove(key);
    }
  }

  /// Removes photo files nothing points at any more (payment QR codes are
  /// kept).
  Future<int> cleanUp() async {
    final inUse = {
      ...await _inventory.photoPaths(),
      ...await _products.photoPaths(),
      ...await _settings.paymentQrPaths(),
    };
    return _store.deleteUnused(inUse);
  }

  // ---------------------------------------------------------------------------
  // Payment QR codes (Business): the owner's own Maya / MariBank / BDO QR
  // ---------------------------------------------------------------------------

  /// The saved QR photo for a payment method ('maya', 'maribank', 'bdo'),
  /// or null when none was set up.
  Future<String?> paymentQrPath(String methodId) async {
    final v = await _settings.get(SettingsRepository.paymentQrKey(methodId));
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Picks a QR image (usually a screenshot from the gallery), saves it
  /// encrypted like other business photos and makes it the QR shown at
  /// checkout. Returns the new path, or null if cancelled. The previous
  /// QR image is deleted. Throws [PhotoAccessDenied].
  Future<String?> setPaymentQr(String methodId, {PhotoSource source = PhotoSource.gallery}) async {
    final path = await pick(source);
    if (path == null) return null;
    final old = await paymentQrPath(methodId);
    await _settings.set(SettingsRepository.paymentQrKey(methodId), path);
    if (old != null && old != path) await delete(old);
    return path;
  }

  /// Removes the owner's QR for [methodId].
  Future<void> removePaymentQr(String methodId) async {
    final old = await paymentQrPath(methodId);
    await _settings.remove(SettingsRepository.paymentQrKey(methodId));
    await delete(old);
  }

  // ---------------------------------------------------------------------------
  // One-time encryption of photos saved before v8
  // ---------------------------------------------------------------------------

  Future<bool> needsMigration() async => await _settings.get(SettingsRepository.photosEncrypted) == null;

  /// Encrypts every plain photo, points its record at the new file, then
  /// deletes the plain file (in that order, so a crash midway never loses
  /// a photo). A photo that fails is left as it is and retried next start;
  /// the "done" flag is only set when nothing failed.
  Future<PhotoMigrationProgress> migrateLegacy({void Function(PhotoMigrationProgress p)? onProgress}) async {
    final rows = <(String, int, String)>[
      for (final (id, path) in await _inventory.photoRows()) ('inventory', id, path),
      for (final (id, path) in await _products.photoRows()) ('product', id, path),
    ];
    final todo = rows.where((r) => p.extension(r.$3) != PhotoStore.extension).toList();
    var done = 0, failed = 0;
    void report(bool finished) =>
        onProgress?.call(PhotoMigrationProgress(total: todo.length, done: done, failed: failed, finished: finished));
    report(false);
    for (final (table, id, path) in todo) {
      try {
        Future<void> setPath(String? v) =>
            table == 'inventory' ? _inventory.setPhotoPath(id, v) : _products.setPhotoPath(id, v);
        if (!await _store.exists(path)) {
          await setPath(null); // The file was already gone; drop the broken link.
        } else {
          final raw = await _store.read(path);
          final enc = PhotoCrypto.isEncrypted(raw) ? Uint8List.fromList(raw) : await _crypto.encrypt(raw);
          final newPath = await _store.writeEncrypted(enc);
          await setPath(newPath);
          await _store.delete(path);
        }
        done++;
      } catch (_) {
        failed++;
      }
      report(false);
    }
    if (failed == 0) await _settings.set(SettingsRepository.photosEncrypted, '1');
    final result = PhotoMigrationProgress(total: todo.length, done: done, failed: failed, finished: true);
    onProgress?.call(result);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Backups
  // ---------------------------------------------------------------------------

  /// file name -> base64 of the decrypted photo, for a backup. The backup
  /// file is encrypted with its own password, and another phone can't use
  /// this phone's photo key, so the photos travel decrypted inside it.
  /// Missing or unreadable photos are skipped (their records keep no photo).
  Future<Map<String, String>> exportForBackup(Iterable<String> paths) async {
    final out = <String, String>{};
    for (final path in paths.toSet()) {
      try {
        out[p.basename(path)] = base64Encode(await read(path));
      } catch (_) {
        // Skipped.
      }
    }
    return out;
  }

  /// Encrypts a backup's photos into a temporary folder. Returns backup
  /// file name -> where it will live once committed. Nothing in the real
  /// photo folder changes until [commitRestore]; call [discardRestore] if
  /// the restore fails. Throws if a photo is damaged.
  Future<Map<String, String>> stageForRestore(Map<String, String> photos) async {
    await _store.clearStaging();
    final out = <String, String>{};
    try {
      for (final e in photos.entries) {
        final Uint8List plain;
        try {
          plain = base64Decode(e.value);
        } on FormatException {
          throw const FormatException('A photo in the backup is damaged.');
        }
        final staged = await _store.writeEncrypted(await _crypto.encrypt(plain), staging: true);
        out[e.key] = staged;
      }
      return out;
    } catch (_) {
      await _store.clearStaging();
      rethrow;
    }
  }

  /// Final paths for staged photos (to write into the restored records).
  Future<Map<String, String>> finalPaths(Map<String, String> staged) async =>
      {for (final e in staged.entries) e.key: await _store.finalPathFor(e.value)};

  /// Moves staged photos into the photo folder after the database restore committed.
  Future<void> commitRestore(Map<String, String> staged) async {
    for (final path in staged.values) {
      await _store.commitStaged(path);
    }
    await _store.clearStaging();
  }

  Future<void> discardRestore() => _store.clearStaging();

  // ---------------------------------------------------------------------------
  // Camera photo lost when Android closed the app
  // ---------------------------------------------------------------------------

  Future<void> saveDraft(PhotoDraft draft) => _settings.set(SettingsRepository.photoDraft, draft.toJson());

  /// The camera came back (photo or not): the app wasn't closed.
  Future<void> cameraReturned() async {
    final draft = PhotoDraft.fromJson(await _settings.get(SettingsRepository.photoDraft));
    if (draft != null && draft.awaitingCamera) await saveDraft(draft.copyWith(awaitingCamera: false));
  }

  /// After a save or cancel.
  Future<void> clearDraft() => _settings.remove(SettingsRepository.photoDraft);

  PhotoRecovery get _recovery => PhotoRecovery(
        loadDraft: () => _settings.get(SettingsRepository.photoDraft),
        saveDraft: (json) => json == null ? clearDraft() : _settings.set(SettingsRepository.photoDraft, json),
        retrieveLost: _store.retrieveLost,
        importPhoto: (working) async {
          final plain = await _store.read(working);
          final path = await _store.writeEncrypted(await _crypto.encrypt(plain));
          _remember(path, plain);
          return path;
        },
        discardWorkingCopy: _store.deleteWorkingCopy,
      );

  /// On start-up: a form to reopen with its recovered photo, if the app was
  /// closed while the camera was open. Kept until a form takes it.
  Future<RecoveredForm?> recoverLost() async {
    final r = await _recovery.recover();
    if (r != null) _pendingRecovery = r;
    return _pendingRecovery;
  }

  /// For a photo form being built: the recovered draft meant for it, once.
  RecoveredForm? takeRecovery(String form, int? recordId) {
    final r = _pendingRecovery;
    if (r == null || r.draft.form != form || r.draft.recordId != recordId) return null;
    _pendingRecovery = null;
    return r;
  }
}
