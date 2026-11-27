import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PhotoSource { camera, gallery }

/// The user said no to camera / photo access (or turned it off).
class PhotoAccessDenied implements Exception {
  const PhotoAccessDenied(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What `retrieveLostData` found after Android closed the app while the
/// camera was open.
class LostPhoto {
  const LostPhoto({this.path, this.error});
  const LostPhoto.none() : path = null, error = null;

  /// The picker's (compressed, plain) file in the cache, if any.
  final String? path;
  final String? error;
  bool get isEmpty => path == null && error == null;
}

/// Photo files on disk. Only the picker's working copy is ever plain; it is
/// deleted as soon as it has been encrypted. Saved photos are encrypted
/// files in the app's private folder (`<app documents>/business_photos`),
/// which other apps can't read. Nothing is uploaded.
///
/// Permissions: the camera opens through the system camera app and the
/// gallery through the system photo picker, so the app itself needs no
/// CAMERA or storage permission on Android.
class PhotoStore {
  PhotoStore({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  static const folderName = 'business_photos';
  static const stagingName = 'restore_photos_tmp';
  static const extension = '.enc';

  /// Longest side in pixels, and JPEG quality (0-100). A phone photo of
  /// several MB ends up around 100-250 KB before encryption.
  static const maxSide = 1080.0;
  static const quality = 70;

  final _random = Random.secure();

  Future<Directory> _dir(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> folder() => _dir(folderName);
  Future<Directory> stagingFolder() => _dir(stagingName);

  String newName() => '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(1 << 30)}$extension';

  /// Takes or picks a photo, compressed by the picker. Returns the plain
  /// working copy's path (delete it with [deleteWorkingCopy] right after
  /// use), or null if the user cancelled.
  Future<String?> pickWorkingCopy(PhotoSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: quality,
        requestFullMetadata: false,
      );
      return picked?.path;
    } on PlatformException catch (e) {
      throw _accessError(e, source);
    }
  }

  static Object _accessError(PlatformException e, PhotoSource? source) {
    final code = e.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return PhotoAccessDenied(source == PhotoSource.gallery
          ? 'Photo access is off. Allow it in your phone settings, or take a photo instead.'
          : 'Camera access is off. Allow it in your phone settings, or choose a photo from the gallery.');
    }
    if (code.contains('no_available_camera')) {
      return const PhotoAccessDenied('No camera was found. Choose a photo from the gallery instead.');
    }
    return e;
  }

  /// Android only: a photo taken just before Android closed the app.
  /// Never throws; problems come back in [LostPhoto.error].
  Future<LostPhoto> retrieveLost() async {
    if (!Platform.isAndroid) return const LostPhoto.none();
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty) return const LostPhoto.none();
      final file = response.file ?? ((response.files?.isNotEmpty ?? false) ? response.files!.first : null);
      if (file != null) return LostPhoto(path: file.path);
      final e = response.exception;
      if (e != null) {
        final err = _accessError(e, PhotoSource.camera);
        return LostPhoto(error: err is PhotoAccessDenied ? err.message : 'The camera reported a problem: ${e.message ?? e.code}');
      }
      return const LostPhoto.none();
    } catch (e) {
      return LostPhoto(error: 'Could not get the photo back: $e');
    }
  }

  Future<Uint8List> read(String path) => File(path).readAsBytes();

  /// Writes already-encrypted bytes as a new file in the photo folder (or
  /// the restore staging folder). Written to a ".part" file first, then
  /// renamed, so a crash never leaves half a photo under the real name.
  Future<String> writeEncrypted(Uint8List bytes, {bool staging = false}) async {
    final dir = staging ? await stagingFolder() : await folder();
    final dest = p.join(dir.path, newName());
    final part = File('$dest.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(dest);
    return dest;
  }

  /// Moves a staged restore photo into the photo folder (same name).
  Future<String> commitStaged(String stagedPath) async {
    final dest = p.join((await folder()).path, p.basename(stagedPath));
    await File(stagedPath).rename(dest);
    return dest;
  }

  /// Where a staged photo will end up after [commitStaged].
  Future<String> finalPathFor(String stagedPath) async => p.join((await folder()).path, p.basename(stagedPath));

  Future<void> clearStaging() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, stagingName));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Deletes the picker's plain working copy. Only files in the app's cache
  /// are touched, never the user's gallery originals.
  Future<void> deleteWorkingCopy(String path) async {
    try {
      final tmp = await getTemporaryDirectory();
      if (p.isWithin(tmp.path, path)) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {
      // The OS clears the cache anyway.
    }
  }

  /// Deletes a file in the photo folder (only there).
  Future<void> delete(String? path) async {
    if (path == null) return;
    final dir = await folder();
    if (!p.isWithin(dir.path, path)) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  Future<bool> exists(String path) => File(path).exists();

  /// Deletes every stored photo ("Delete all my data").
  Future<void> deleteAll() async {
    final base = await getApplicationDocumentsDirectory();
    for (final name in [folderName, stagingName]) {
      final dir = Directory(p.join(base.path, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  /// Removes photos no item or product points at any more. Files written
  /// within [keepNewerThan] are kept: they may belong to a form that is
  /// still open (or reopening after unlock) and not saved yet.
  Future<int> deleteUnused(Set<String> inUse, {Duration keepNewerThan = Duration.zero}) async {
    final dir = await folder();
    final cutoff = DateTime.now().subtract(keepNewerThan);
    var removed = 0;
    await for (final e in dir.list()) {
      if (e is! File || inUse.contains(e.path)) continue;
      if (keepNewerThan > Duration.zero) {
        try {
          if ((await e.lastModified()).isAfter(cutoff)) continue;
        } catch (_) {
          continue; // Can't tell its age: keep it for now.
        }
      }
      await e.delete();
      removed++;
    }
    return removed;
  }
}
