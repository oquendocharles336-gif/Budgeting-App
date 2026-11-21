import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/photo_service.dart';
import 'core_providers.dart';

/// The one-time encryption of photos saved before photos were encrypted.
/// Null = not running (nothing to do, or not started).
class PhotoMigrationController extends Notifier<PhotoMigrationProgress?> {
  bool _started = false;

  @override
  PhotoMigrationProgress? build() => null;

  /// Runs once per unlock when needed. Safe to call repeatedly.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final photos = ref.read(photoServiceProvider);
    try {
      if (!await photos.needsMigration()) {
        await photos.cleanUp(); // photo files no record points at
        return;
      }
      final result = await photos.migrateLegacy(onProgress: (p) => state = p);
      if (result.done > 0) ref.read(dataRevisionProvider.notifier).bump();
      // Leave the finished state up briefly so the line can say "done".
      await Future<void>.delayed(const Duration(seconds: 3));
      state = null;
    } catch (e) {
      debugPrint('Photo encryption step failed, will retry next start: $e');
      state = null;
    }
  }
}

final photoMigrationProvider =
    NotifierProvider<PhotoMigrationController, PhotoMigrationProgress?>(PhotoMigrationController.new);
