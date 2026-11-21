import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ApkUpdateException implements Exception {
  const ApkUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// How the system installer step ended.
enum InstallOutcome {
  /// Android installed it (normally the app restarts before this arrives).
  installed,

  /// The user closed the "Update Pitaka?" screen.
  cancelled,

  /// The user didn't allow Pitaka to install apps.
  permissionDenied,

  /// The installer reported a problem (e.g. signed with a different key).
  failed,
}

/// Stops a running download.
class DownloadCancel {
  bool _cancelled = false;
  HttpClient? _client;
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }
}

/// Downloads the update's APK inside the app and hands it to Android's
/// package installer, so the user never leaves for the browser.
///
/// Android always shows its own "Update this app?" confirmation for an app
/// installed outside the Play Store (no app can skip it), and the first time
/// it asks to allow "Install unknown apps" for Pitaka. The update keeps all
/// data, as long as it is signed with the same key.
class ApkUpdater {
  ApkUpdater._();

  static const _channel = MethodChannel('pitaka/update');
  static const timeout = Duration(seconds: 30);

  /// Max APK size accepted (a safety limit, far above Pitaka's size).
  static const maxBytes = 300 * 1024 * 1024;

  static bool get supported => Platform.isAndroid;

  static Future<Directory> _dir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Deletes downloaded APKs (after updating they're not needed). Never throws.
  static Future<void> clearDownloads() async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Only cache files; Android clears them eventually anyway.
    }
  }

  /// Downloads [url] to the app's cache. [onProgress] gets bytes received
  /// and the total when known. Checks the size and, when GitHub gives one,
  /// the SHA-256, so a broken or swapped file is never installed.
  static Future<File> download(
    Uri url, {
    required String version,
    int? expectedSize,
    String? expectedSha256,
    required void Function(int received, int? total) onProgress,
    DownloadCancel? cancel,
  }) async {
    if (url.scheme != 'https') throw const ApkUpdateException('The download link must use https://');
    await clearDownloads();
    final dir = await _dir();
    final part = File('${dir.path}/pitaka-$version.apk.part');
    final done = File('${dir.path}/pitaka-$version.apk');
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'Pitaka-updater';
    cancel?._client = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      // GitHub sends the file from another host: follow its redirect.
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw ApkUpdateException('The download failed (GitHub answered ${response.statusCode}). Try again later.');
      }
      final length = response.contentLength > 0 ? response.contentLength : null;
      final total = expectedSize ?? length;
      if (total != null && total > maxBytes) throw const ApkUpdateException('The update file is too large.');
      sink = part.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      onProgress(0, total);
      await for (final chunk in response.timeout(timeout)) {
        if (cancel?.isCancelled ?? false) throw const ApkUpdateException('Download cancelled.');
        received += chunk.length;
        if (received > maxBytes) throw const ApkUpdateException('The update file is too large.');
        sink.add(chunk);
        hasher.add(chunk);
        onProgress(received, total);
      }
      hasher.close();
      await sink.close();
      sink = null;
      if (cancel?.isCancelled ?? false) throw const ApkUpdateException('Download cancelled.');
      if (total != null && received != total) {
        throw const ApkUpdateException('The download was incomplete. Try again.');
      }
      final hash = digest.value?.toString();
      if (expectedSha256 != null && hash != expectedSha256) {
        throw const ApkUpdateException('The downloaded file doesn\'t match the release, so it wasn\'t installed. Try again.');
      }
      return await part.rename(done.path);
    } on SocketException {
      throw ApkUpdateException((cancel?.isCancelled ?? false) ? 'Download cancelled.' : 'The connection was lost. Check your internet and try again.');
    } on TimeoutException {
      throw const ApkUpdateException('The download timed out. Check your connection and try again.');
    } on HttpException {
      throw ApkUpdateException((cancel?.isCancelled ?? false) ? 'Download cancelled.' : 'The connection was interrupted. Try again.');
    } on FileSystemException {
      throw const ApkUpdateException('Not enough free space on the phone for the update.');
    } finally {
      await sink?.close();
      client.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {
          // A leftover partial file is cleared before the next download.
        }
      }
    }
  }

  /// Opens Android's installer for [apk]. Waits until the user comes back
  /// from it (or from the "Install unknown apps" setting the first time).
  static Future<InstallOutcome> install(File apk) async {
    try {
      final r = await _channel.invokeMethod<String>('installApk', {'path': apk.path});
      return switch (r) {
        'installed' => InstallOutcome.installed,
        'cancelled' => InstallOutcome.cancelled,
        'permission_denied' => InstallOutcome.permissionDenied,
        _ => InstallOutcome.failed,
      };
    } on PlatformException catch (e) {
      throw ApkUpdateException('Could not open the installer: ${e.message ?? e.code}');
    } on MissingPluginException {
      throw const ApkUpdateException('Installing updates from the app isn\'t available on this device.');
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
