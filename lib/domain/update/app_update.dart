import 'dart:convert';

/// A semantic version ("1.2.3", "v1.2.3", "1.2.0-beta.1", "1.2.0+5").
///
/// A leading "v" is ignored, missing minor / patch count as 0 ("v2" =
/// 2.0.0), and build metadata after "+" is ignored when comparing, as the
/// SemVer rules say. A pre-release ("1.2.0-beta") is older than the
/// release ("1.2.0").
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.preRelease = const []]);

  final int major;
  final int minor;
  final int patch;

  /// Dot-separated pre-release parts, e.g. ["beta", "1"]. Empty = release.
  final List<String> preRelease;

  bool get isPreRelease => preRelease.isNotEmpty;

  static final _pattern = RegExp(
    r'^[vV]?(\d{1,6})(?:\.(\d{1,6}))?(?:\.(\d{1,6}))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  /// Null when [text] isn't a version.
  static AppVersion? tryParse(String? text) {
    if (text == null) return null;
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    final pre = m[4];
    return AppVersion(
      int.parse(m[1]!),
      int.parse(m[2] ?? '0'),
      int.parse(m[3] ?? '0'),
      pre == null ? const [] : pre.split('.').where((p) => p.isNotEmpty).toList(),
    );
  }

  @override
  int compareTo(AppVersion o) {
    if (major != o.major) return major.compareTo(o.major);
    if (minor != o.minor) return minor.compareTo(o.minor);
    if (patch != o.patch) return patch.compareTo(o.patch);
    // A release is newer than any of its pre-releases.
    if (preRelease.isEmpty || o.preRelease.isEmpty) {
      return preRelease.isEmpty == o.preRelease.isEmpty ? 0 : (preRelease.isEmpty ? 1 : -1);
    }
    for (var i = 0; i < preRelease.length && i < o.preRelease.length; i++) {
      final a = preRelease[i], b = o.preRelease[i];
      final an = int.tryParse(a), bn = int.tryParse(b);
      final int c;
      if (an != null && bn != null) {
        c = an.compareTo(bn);
      } else if (an != null) {
        c = -1; // Numbers sort before words.
      } else if (bn != null) {
        c = 1;
      } else {
        c = a.compareTo(b);
      }
      if (c != 0) return c;
    }
    return preRelease.length.compareTo(o.preRelease.length);
  }

  bool operator >(AppVersion o) => compareTo(o) > 0;
  bool operator <(AppVersion o) => compareTo(o) < 0;
  bool operator >=(AppVersion o) => compareTo(o) >= 0;
  bool operator <=(AppVersion o) => compareTo(o) <= 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() => '$major.$minor.$patch${preRelease.isEmpty ? '' : '-${preRelease.join('.')}'}';
}

/// The newest release, read from the GitHub Releases API
/// (`/repos/<OWNER>/<REPO>/releases/latest`).
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.downloadUrl,
    required this.pageUrl,
    required this.notes,
    this.name,
    this.releasedAt,
    this.isApk = false,
    this.apkSize,
    this.apkSha256,
  });

  /// From the tag ("v1.2.0" -> 1.2.0).
  final AppVersion version;
  final String tag;
  final String? name;

  /// The APK asset when the release has one, else the release page.
  final Uri downloadUrl;

  /// Whether [downloadUrl] is an APK file (not the release page).
  final bool isApk;

  /// The APK's size in bytes, from GitHub (to show progress and check the
  /// download is complete).
  final int? apkSize;

  /// The APK's SHA-256 (lower-case hex) when GitHub lists one (the asset's
  /// `digest`), to check the download wasn't damaged or swapped.
  final String? apkSha256;

  /// The release page on github.com.
  final Uri pageUrl;
  final List<String> notes;
  final DateTime? releasedAt;

  static const maxNotes = 30;
  static const maxNoteLength = 300;

  /// Checks everything; throws [FormatException] with a readable message
  /// for anything unexpected, so a broken answer is reported instead of shown.
  static ReleaseInfo parseGitHub(String text) {
    final Object? d;
    try {
      d = jsonDecode(text);
    } on FormatException {
      throw const FormatException('GitHub sent something that isn\'t release information.');
    }
    if (d is! Map<String, dynamic>) throw const FormatException('GitHub sent release information in an unexpected shape.');
    if (d['draft'] == true || d['prerelease'] == true) {
      throw const FormatException('The latest release is a draft or pre-release.');
    }
    final tag = d['tag_name'];
    if (tag is! String || tag.trim().isEmpty) throw const FormatException('The latest release has no tag.');
    final version = AppVersion.tryParse(tag);
    if (version == null) {
      throw FormatException('The release tag "$tag" isn\'t a version. Tag releases like v1.2.0.');
    }
    final page = _https(d['html_url']);
    if (page == null) throw const FormatException('The release has no https:// page link.');

    Uri? apk;
    int? apkSize;
    String? apkSha256;
    final assets = d['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map<String, dynamic>) continue;
        final name = '${a['name'] ?? ''}'.toLowerCase();
        final url = _https(a['browser_download_url']);
        if (url != null && name.endsWith('.apk')) {
          apk = url;
          final size = a['size'];
          if (size is int && size > 0) apkSize = size;
          final digest = a['digest'];
          if (digest is String && digest.toLowerCase().startsWith('sha256:')) {
            final hex = digest.substring(7).toLowerCase();
            if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) apkSha256 = hex;
          }
          break;
        }
      }
    }
    final body = d['body'];
    final published = d['published_at'];
    final name = d['name'];
    return ReleaseInfo(
      version: version,
      tag: tag.trim(),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      downloadUrl: apk ?? page,
      isApk: apk != null,
      apkSize: apkSize,
      apkSha256: apkSha256,
      pageUrl: page,
      notes: body is String ? notesFromMarkdown(body) : const [],
      releasedAt: published is String ? DateTime.tryParse(published)?.toLocal() : null,
    );
  }

  static Uri? _https(Object? v) {
    if (v is! String) return null;
    final u = Uri.tryParse(v);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty ? u : null;
  }

  /// Release notes as plain lines: markdown bullets, headings, emphasis
  /// and links are reduced to text (never shown as HTML or links).
  static List<String> notesFromMarkdown(String body) {
    final out = <String>[];
    for (final raw in const LineSplitter().convert(body)) {
      var t = raw.trim();
      if (t.isEmpty || t.startsWith('<!--') || RegExp(r'^[-*_=]{3,}$').hasMatch(t)) continue;
      t = t
          .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
          .replaceFirst(RegExp(r'^([-*+]|\d+[.)])\s+'), '')
          .replaceFirst(RegExp(r'^\[[ xX]\]\s+'), '')
          .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
          .replaceAll(RegExp(r'\*{1,3}|`+|__'), '')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (t.isEmpty) continue;
      out.add(t.length > maxNoteLength ? '${t.substring(0, maxNoteLength)}…' : t);
      if (out.length >= maxNotes) break;
    }
    return out;
  }
}

/// Pure decisions about update checks (unit tested).
class UpdatePolicy {
  UpdatePolicy._();

  /// True only when the release is newer than the installed version.
  static bool isNewer({required String installed, required ReleaseInfo release}) {
    final current = AppVersion.tryParse(installed);
    // An unreadable installed version: offer the release rather than hide it.
    return current == null || release.version > current;
  }

  /// Whether to pop up the prompt. A skipped version isn't shown again
  /// (a later one is).
  static bool shouldPrompt({required String installed, required ReleaseInfo release, String? skippedVersion}) {
    if (!isNewer(installed: installed, release: release)) return false;
    final skipped = AppVersion.tryParse(skippedVersion);
    return skipped == null || release.version > skipped;
  }

  /// At most one automatic check per [every].
  static bool checkDue({DateTime? lastCheck, required DateTime now, required Duration every}) =>
      lastCheck == null || now.difference(lastCheck) >= every || now.isBefore(lastCheck);
}

/// One version's notes, built into the app.
class ChangelogEntry {
  const ChangelogEntry({required this.version, required this.build, required this.notes, this.date});
  final String version;
  final int build;
  final String? date;
  final List<String> notes;
}

class WhatsNew {
  WhatsNew._();

  /// "What's new" shows at most this many versions: the latest update and
  /// the one before it.
  static const maxVersions = 2;

  /// Whether "What's new" should show: only when [current] is higher than
  /// the [lastSeen] version. Never for a fresh install ([lastSeen] null).
  static bool shouldShow({required String? lastSeen, required String current}) {
    final seen = AppVersion.tryParse(lastSeen);
    final now = AppVersion.tryParse(current);
    if (seen == null || now == null) return false;
    return now > seen;
  }

  /// Entries the user hasn't seen: newer than [lastSeen], up to the
  /// installed [current], newest first, at most [maxVersions] (the latest
  /// update and the one before it). Empty when [shouldShow] is false.
  static List<ChangelogEntry> since(List<ChangelogEntry> all, {required String? lastSeen, required String current}) {
    if (!shouldShow(lastSeen: lastSeen, current: current)) return const [];
    final seen = AppVersion.tryParse(lastSeen)!;
    final now = AppVersion.tryParse(current)!;
    final out = <ChangelogEntry>[];
    for (final e in all) {
      final v = AppVersion.tryParse(e.version);
      if (v != null && v > seen && v <= now) out.add(e);
    }
    out.sort((a, b) => AppVersion.tryParse(b.version)!.compareTo(AppVersion.tryParse(a.version)!));
    return out.take(maxVersions).toList();
  }

  /// For Settings > "What's new": the installed version's notes and the
  /// previous version's, newest first.
  static List<ChangelogEntry> latest(List<ChangelogEntry> all, String current) {
    final now = AppVersion.tryParse(current);
    if (now == null) return const [];
    final out = [
      for (final e in all)
        if (AppVersion.tryParse(e.version) case final v? when v <= now) e,
    ]..sort((a, b) => AppVersion.tryParse(b.version)!.compareTo(AppVersion.tryParse(a.version)!));
    return out.take(maxVersions).toList();
  }

  /// The entry for the installed version (Settings > What's new).
  static ChangelogEntry? current(List<ChangelogEntry> all, String current) {
    final now = AppVersion.tryParse(current);
    if (now == null) return null;
    for (final e in all) {
      if (AppVersion.tryParse(e.version) == now) return e;
    }
    return null;
  }

  /// The changelog version for an old build number (records written by
  /// versions that saved the build instead of the version name).
  static String? versionForBuild(List<ChangelogEntry> all, int build) {
    for (final e in all) {
      if (e.build == build) return e.version;
    }
    return null;
  }
}
