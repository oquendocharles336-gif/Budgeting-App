import '../../core/app_update_config.dart';
import '../../core/changelog.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/release_feed.dart';
import '../update/app_update.dart';

export '../../data/sources/release_feed.dart' show InstalledVersion, ReleaseFeedException, UpdateErrorKind;
export '../update/app_update.dart' show AppVersion, ChangelogEntry, ReleaseInfo;

/// The three outcomes of a check.
enum UpdateStatus { upToDate, available, error }

/// What a check found.
class UpdateCheck {
  const UpdateCheck._({
    required this.status,
    this.installed,
    this.release,
    this.shouldPrompt = false,
    this.errorMessage,
    this.errorKind,
  });

  const UpdateCheck.upToDate({required InstalledVersion installed, required ReleaseInfo release})
      : this._(status: UpdateStatus.upToDate, installed: installed, release: release);

  const UpdateCheck.available({required InstalledVersion installed, required ReleaseInfo release, required bool shouldPrompt})
      : this._(status: UpdateStatus.available, installed: installed, release: release, shouldPrompt: shouldPrompt);

  const UpdateCheck.error(String message, {UpdateErrorKind kind = UpdateErrorKind.server, InstalledVersion? installed})
      : this._(status: UpdateStatus.error, errorMessage: message, errorKind: kind, installed: installed);

  final UpdateStatus status;
  final InstalledVersion? installed;

  /// The latest GitHub release (null for errors).
  final ReleaseInfo? release;

  /// For [UpdateStatus.available]: false when the user skipped this version
  /// (the automatic check then stays quiet; "Check now" still shows it).
  final bool shouldPrompt;

  /// For [UpdateStatus.error]: what went wrong, readable.
  final String? errorMessage;
  final UpdateErrorKind? errorKind;

  bool get isError => status == UpdateStatus.error;
}

/// "A newer version is available" (GitHub Releases) and "What's new" after
/// updating (built-in changelog).
class UpdateService {
  UpdateService({
    required this._settings,
    required Future<String> Function() fetchRelease,
    required this._installed,
    DateTime Function()? clock,
  })  : _fetch = fetchRelease,
        _clock = clock ?? DateTime.now;

  final SettingsRepository _settings;
  final Future<String> Function() _fetch;
  final Future<InstalledVersion> Function() _installed;
  final DateTime Function() _clock;

  /// "OWNER/REPO" the app checks (for display).
  String get repository => AppUpdateConfig.githubRepository;

  Future<InstalledVersion> installed() => _installed();

  /// On unless the user turned it off in Settings.
  Future<bool> enabled() async => await _settings.get(SettingsRepository.updateCheckEnabled) != '0';

  Future<void> setEnabled(bool on) => _settings.set(SettingsRepository.updateCheckEnabled, on ? '1' : '0');

  /// The automatic check (at most once a day, only when enabled). Returns
  /// null when no check ran or it failed (offline: it tries again next
  /// time, silently). Never throws.
  Future<UpdateCheck?> checkIfDue() async {
    try {
      if (!await enabled()) return null;
      final last = int.tryParse(await _settings.get(SettingsRepository.updateLastCheck) ?? '');
      final lastCheck = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
      if (!UpdatePolicy.checkDue(lastCheck: lastCheck, now: _clock(), every: AppUpdateConfig.checkEvery)) return null;
      final check = await checkNow();
      return check.isError ? null : check;
    } catch (_) {
      return null;
    }
  }

  /// "Check now" in Settings: always runs, never throws. Returns up to
  /// date, update available (with the download link in the release), or
  /// an error with a readable message.
  Future<UpdateCheck> checkNow() async {
    InstalledVersion? installed;
    try {
      installed = await _installed();
      final release = ReleaseInfo.parseGitHub(await _fetch());
      await _settings.set(SettingsRepository.updateLastCheck, '${_clock().millisecondsSinceEpoch}');
      if (!UpdatePolicy.isNewer(installed: installed.version, release: release)) {
        return UpdateCheck.upToDate(installed: installed, release: release);
      }
      final skipped = await _skippedVersion();
      return UpdateCheck.available(
        installed: installed,
        release: release,
        shouldPrompt: UpdatePolicy.shouldPrompt(installed: installed.version, release: release, skippedVersion: skipped),
      );
    } on ReleaseFeedException catch (e) {
      return UpdateCheck.error(e.message, kind: e.kind, installed: installed);
    } on FormatException catch (e) {
      return UpdateCheck.error(e.message, kind: UpdateErrorKind.badData, installed: installed);
    } catch (e) {
      return UpdateCheck.error('Could not check for updates: $e', installed: installed);
    }
  }

  Future<String?> _skippedVersion() async {
    final v = await _settings.get(SettingsRepository.updateSkippedVersion);
    if (v != null) return v;
    // Skips saved by 1.1 were build numbers.
    final build = int.tryParse(await _settings.get(SettingsRepository.updateSkippedBuild) ?? '');
    return build == null ? null : WhatsNew.versionForBuild(changelog, build);
  }

  /// "Skip this version": not shown automatically again until a newer one.
  Future<void> skip(AppVersion version) => _settings.set(SettingsRepository.updateSkippedVersion, '$version');

  /// "What's new" to show once after an update. Returns nothing on a fresh
  /// install, or when this version (or a newer one) was already seen.
  ///
  /// The installed version is saved as seen BEFORE anything is shown, so
  /// closing or locking the app while the sheet is open doesn't bring it
  /// back. [hasExistingData] tells an update from 1.0 (which saved nothing)
  /// apart from a fresh install.
  Future<List<ChangelogEntry>> takeWhatsNew({required bool hasExistingData}) async {
    final current = (await _installed()).version;
    final lastSeen = await _lastSeenVersion(hasExistingData: hasExistingData);
    final entries = WhatsNew.since(changelog, lastSeen: lastSeen, current: current);
    // Never move the record backwards (e.g. after installing an older APK).
    final seen = AppVersion.tryParse(lastSeen);
    final now = AppVersion.tryParse(current);
    if (seen == null || now == null || now > seen) {
      await _settings.set(SettingsRepository.whatsNewSeenVersion, current);
    }
    return entries;
  }

  Future<String?> _lastSeenVersion({required bool hasExistingData}) async {
    final saved = await _settings.get(SettingsRepository.whatsNewSeenVersion);
    if (saved != null) return saved;
    // 1.1 saved the build number instead of the version.
    final build = int.tryParse(await _settings.get(SettingsRepository.whatsNewSeenBuild) ?? '');
    if (build != null) return WhatsNew.versionForBuild(changelog, build) ?? '0.0.0';
    // 1.0 saved nothing: data means it's an update from the first release;
    // no data means a fresh install (nothing to show).
    return hasExistingData ? changelog.last.version : null;
  }

  /// This version's notes, for Settings.
  Future<ChangelogEntry?> currentNotes() async => WhatsNew.current(changelog, (await _installed()).version);
}
