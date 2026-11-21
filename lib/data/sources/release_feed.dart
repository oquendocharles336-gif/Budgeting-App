import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// The installed app's version (from the APK).
class InstalledVersion {
  const InstalledVersion({required this.version, required this.build});

  /// pubspec.yaml's version name, e.g. "1.2.0".
  final String version;
  final int build;
}

Future<InstalledVersion> readInstalledVersion() async {
  final info = await PackageInfo.fromPlatform();
  return InstalledVersion(version: info.version, build: int.tryParse(info.buildNumber) ?? 0);
}

/// Why an update check failed, so the screen can say what to do.
enum UpdateErrorKind { offline, timeout, rateLimited, noReleases, server, badData, config }

class ReleaseFeedException implements Exception {
  const ReleaseFeedException(this.message, {this.kind = UpdateErrorKind.server});
  final String message;
  final UpdateErrorKind kind;
  @override
  String toString() => message;
}

/// Reads the latest release from the GitHub Releases API. This is the
/// app's ONLY network request: a plain HTTPS GET of public release info.
/// Nothing about the user or their data is sent (no account, no device id,
/// no analytics, no token).
class GitHubReleaseFeed {
  GitHubReleaseFeed(this.uri, {this.repository = ''});

  /// `https://api.github.com/repos/<OWNER>/<REPO>/releases/latest`.
  final Uri uri;

  /// "OWNER/REPO", for messages.
  final String repository;

  static const timeout = Duration(seconds: 12);

  /// Release JSON with long notes and many assets stays well under this.
  static const maxBytes = 1024 * 1024;

  static final _repoPattern = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

  /// The release JSON. Throws [ReleaseFeedException] with a readable
  /// message and a [UpdateErrorKind].
  Future<String> fetch() async {
    if (!_repoPattern.hasMatch(repository) || uri.scheme != 'https') {
      throw ReleaseFeedException(
        'The GitHub repository "$repository" isn\'t valid. Set it as OWNER/REPO in lib/core/app_update_config.dart.',
        kind: UpdateErrorKind.config,
      );
    }
    final client = HttpClient()
      ..connectionTimeout = timeout
      // GitHub's API requires a User-Agent.
      ..userAgent = 'Pitaka-update-check';
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.maxRedirects = 3;
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(timeout);
      final body = await _readBody(response);
      final code = response.statusCode;
      if (code == HttpStatus.ok) return body;
      if (code == HttpStatus.notFound) {
        throw ReleaseFeedException(
          'No published release found for $repository. Publish a release on GitHub '
          '(not a draft or pre-release), and check that the repository is public.',
          kind: UpdateErrorKind.noReleases,
        );
      }
      final remaining = response.headers.value('x-ratelimit-remaining');
      if (code == 429 || (code == HttpStatus.forbidden && remaining == '0')) {
        final reset = int.tryParse(response.headers.value('x-ratelimit-reset') ?? '');
        final at = reset == null ? null : DateTime.fromMillisecondsSinceEpoch(reset * 1000);
        final when = at == null ? 'later' : 'after ${_hhmm(at)}';
        throw ReleaseFeedException(
          'GitHub\'s limit for update checks from this network was reached. Try again $when.',
          kind: UpdateErrorKind.rateLimited,
        );
      }
      throw ReleaseFeedException('GitHub answered $code. Try again later.', kind: UpdateErrorKind.server);
    } on SocketException {
      throw const ReleaseFeedException('No internet connection.', kind: UpdateErrorKind.offline);
    } on TimeoutException {
      throw const ReleaseFeedException('The update check timed out. Check your connection.', kind: UpdateErrorKind.timeout);
    } on HandshakeException {
      throw const ReleaseFeedException('Could not make a secure connection to GitHub.', kind: UpdateErrorKind.offline);
    } on HttpException {
      throw const ReleaseFeedException('The connection to GitHub was interrupted.', kind: UpdateErrorKind.offline);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _readBody(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const ReleaseFeedException('The release information is too large.', kind: UpdateErrorKind.badData);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
