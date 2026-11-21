import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// The installed app's version (from the APK).
class InstalledVersion {
  const InstalledVersion({required this.version, required this.build});
  final String version;
  final int build;
}

Future<InstalledVersion> readInstalledVersion() async {
  final info = await PackageInfo.fromPlatform();
  return InstalledVersion(version: info.version, build: int.tryParse(info.buildNumber) ?? 0);
}

class ReleaseFeedException implements Exception {
  const ReleaseFeedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads the hosted version.json. This is the app's ONLY network
/// request: a plain HTTPS GET of one small public file. Nothing about the
/// user or their data is sent (no account, no device id, no analytics).
class ReleaseFeed {
  ReleaseFeed(this.url);
  final String url;

  static const timeout = Duration(seconds: 10);
  static const maxBytes = 64 * 1024;

  Future<String> fetch() async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') throw const ReleaseFeedException('The update address must use https://');
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'Pitaka-update-check';
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.maxRedirects = 3;
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw ReleaseFeedException('The update server answered ${response.statusCode}.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) throw const ReleaseFeedException('The version file is too large.');
      }
      return utf8.decode(bytes);
    } on SocketException {
      throw const ReleaseFeedException('No internet connection.');
    } on TimeoutException {
      throw const ReleaseFeedException('The update check timed out.');
    } on HandshakeException {
      throw const ReleaseFeedException('Could not make a secure connection.');
    } finally {
      client.close(force: true);
    }
  }
}
