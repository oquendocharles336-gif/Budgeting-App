import 'dart:convert';

/// "1.2.3" compared part by part.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$');

  /// Null when [text] isn't "x.y.z".
  static AppVersion? tryParse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  @override
  int compareTo(AppVersion o) =>
      major != o.major ? major.compareTo(o.major) : (minor != o.minor ? minor.compareTo(o.minor) : patch.compareTo(o.patch));

  @override
  String toString() => '$major.$minor.$patch';
}

/// The newest release, as described by the hosted version.json.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.notes,
    this.minSupportedBuild,
    this.releasedAt,
    this.sha256,
  });

  final String version;

  /// The number after "+" in pubspec.yaml's version (Android versionCode).
  final int build;
  final Uri apkUrl;
  final List<String> notes;

  /// Builds older than this get a "required update" message (no skipping).
  final int? minSupportedBuild;
  final DateTime? releasedAt;

  /// Optional checksum shown to the user, to compare with the download.
  final String? sha256;

  static const maxNotes = 30;
  static const maxNoteLength = 300;

  /// Checks everything; throws [FormatException] for anything unexpected,
  /// so a broken or tampered file is ignored instead of shown.
  static ReleaseInfo parse(String text) {
    final Object? d;
    try {
      d = jsonDecode(text);
    } on FormatException {
      throw const FormatException('The version file is not valid JSON.');
    }
    if (d is! Map<String, dynamic>) throw const FormatException('The version file has the wrong shape.');
    final version = d['latestVersion'];
    if (version is! String || AppVersion.tryParse(version) == null) {
      throw const FormatException('latestVersion must look like "1.2.0".');
    }
    final build = d['latestBuild'];
    if (build is! int || build <= 0) throw const FormatException('latestBuild must be a positive whole number.');
    final min = d['minSupportedBuild'];
    if (min != null && (min is! int || min <= 0)) throw const FormatException('minSupportedBuild must be a whole number.');
    final url = Uri.tryParse('${d['apkUrl'] ?? ''}');
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const FormatException('apkUrl must be an https:// link.');
    }
    final rawNotes = d['notes'] ?? const <Object>[];
    if (rawNotes is! List) throw const FormatException('notes must be a list of text lines.');
    final notes = <String>[];
    for (final n in rawNotes.take(maxNotes)) {
      if (n is! String) throw const FormatException('notes must be a list of text lines.');
      final t = n.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) continue;
      notes.add(t.length > maxNoteLength ? '${t.substring(0, maxNoteLength)}…' : t);
    }
    final sha = d['sha256'];
    final released = d['releasedAt'];
    return ReleaseInfo(
      version: version,
      build: build,
      apkUrl: url,
      notes: notes,
      minSupportedBuild: min as int?,
      releasedAt: released is String ? DateTime.tryParse(released) : null,
      sha256: sha is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha) ? sha.toLowerCase() : null,
    );
  }
}

enum UpdateUrgency {
  /// Already up to date (or the file lists an older version).
  none,

  /// Newer version available.
  optional,

  /// This version is older than `minSupportedBuild`.
  required,
}

/// Pure decisions about update checks (unit tested).
class UpdatePolicy {
  UpdatePolicy._();

  static UpdateUrgency urgency({required int currentBuild, required ReleaseInfo release}) {
    if (release.build <= currentBuild) return UpdateUrgency.none;
    final min = release.minSupportedBuild;
    if (min != null && currentBuild < min) return UpdateUrgency.required;
    return UpdateUrgency.optional;
  }

  /// Whether to show the prompt. A skipped version isn't shown again
  /// (a later one is); a required update is always shown.
  static bool shouldPrompt({required int currentBuild, required ReleaseInfo release, int? skippedBuild}) {
    final u = urgency(currentBuild: currentBuild, release: release);
    if (u == UpdateUrgency.none) return false;
    if (u == UpdateUrgency.required) return true;
    return skippedBuild == null || skippedBuild < release.build;
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

  /// Entries the user hasn't seen: newer than [lastSeenBuild], up to the
  /// installed [currentBuild], newest first. Nothing for a fresh install
  /// ([lastSeenBuild] null).
  static List<ChangelogEntry> since(List<ChangelogEntry> all, {required int? lastSeenBuild, required int currentBuild}) {
    if (lastSeenBuild == null || lastSeenBuild >= currentBuild) return const [];
    return all.where((e) => e.build > lastSeenBuild && e.build <= currentBuild).toList()
      ..sort((a, b) => b.build.compareTo(a.build));
  }

  /// The entry for the installed build (Settings > What's new).
  static ChangelogEntry? current(List<ChangelogEntry> all, int currentBuild) {
    for (final e in all) {
      if (e.build == currentBuild) return e;
    }
    return null;
  }
}
