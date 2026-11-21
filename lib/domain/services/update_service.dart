import '../../core/app_update_config.dart';
import '../../core/changelog.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/release_feed.dart';
import '../update/app_update.dart';

export '../../data/sources/release_feed.dart' show InstalledVersion, ReleaseFeedException;
export '../update/app_update.dart' show ChangelogEntry, ReleaseInfo, UpdateUrgency;

/// What a check found.
class UpdateCheck {
  const UpdateCheck({required this.installed, this.release, this.urgency = UpdateUrgency.none, this.shouldPrompt = false});
  final InstalledVersion installed;
  final ReleaseInfo? release;
  final UpdateUrgency urgency;

  /// False for "up to date" and for a version the user chose to skip.
  final bool shouldPrompt;
}

/// "A newer version is available" (hosted version.json) and "What's new"
/// after updating (built-in changelog).
class UpdateService {
  UpdateService({
    required this._settings,
    required Future<String> Function() fetchFeed,
    required this._installed,
    bool? configured,
    DateTime Function()? clock,
  })  : _fetch = fetchFeed,
        _configured = configured ?? AppUpdateConfig.isConfigured,
        _clock = clock ?? DateTime.now;

  final SettingsRepository _settings;
  final Future<String> Function() _fetch;
  final Future<InstalledVersion> Function() _installed;
  final bool _configured;
  final DateTime Function() _clock;

  bool get configured => _configured;

  Future<InstalledVersion> installed() => _installed();

  /// On unless the user turned it off in Settings.
  Future<bool> enabled() async => await _settings.get(SettingsRepository.updateCheckEnabled) != '0';

  Future<void> setEnabled(bool on) => _settings.set(SettingsRepository.updateCheckEnabled, on ? '1' : '0');

  /// The automatic check (at most once a day, only when enabled and set
  /// up). Returns null when no check ran. Never throws.
  Future<UpdateCheck?> checkIfDue() async {
    try {
      if (!_configured || !await enabled()) return null;
      final last = int.tryParse(await _settings.get(SettingsRepository.updateLastCheck) ?? '');
      final lastCheck = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
      if (!UpdatePolicy.checkDue(lastCheck: lastCheck, now: _clock(), every: AppUpdateConfig.checkEvery)) return null;
      return await checkNow();
    } catch (_) {
      return null; // Offline or a bad file: try again next time, silently.
    }
  }

  /// "Check now" in Settings: always runs; throws [ReleaseFeedException]
  /// or [FormatException] with a readable message.
  Future<UpdateCheck> checkNow() async {
    if (!_configured) throw const ReleaseFeedException('Update checks aren\'t set up in this build.');
    final installed = await _installed();
    final release = ReleaseInfo.parse(await _fetch());
    await _settings.set(SettingsRepository.updateLastCheck, '${_clock().millisecondsSinceEpoch}');
    final skipped = int.tryParse(await _settings.get(SettingsRepository.updateSkippedBuild) ?? '');
    return UpdateCheck(
      installed: installed,
      release: release,
      urgency: UpdatePolicy.urgency(currentBuild: installed.build, release: release),
      shouldPrompt: UpdatePolicy.shouldPrompt(currentBuild: installed.build, release: release, skippedBuild: skipped),
    );
  }

  /// "Skip this version": not shown again until a newer one comes out.
  Future<void> skip(int build) => _settings.set(SettingsRepository.updateSkippedBuild, '$build');

  /// Notes to show once after an update (empty after a fresh install).
  /// [hasExistingData] tells an update from a version before this feature
  /// (data, no record) apart from a fresh install (no data).
  Future<List<ChangelogEntry>> pendingWhatsNew({required bool hasExistingData}) async {
    final installed = await _installed();
    var lastSeen = int.tryParse(await _settings.get(SettingsRepository.whatsNewSeenBuild) ?? '');
    if (lastSeen == null && hasExistingData) lastSeen = 1; // the first release had no record
    final entries = WhatsNew.since(changelog, lastSeenBuild: lastSeen, currentBuild: installed.build);
    if (entries.isEmpty) await markWhatsNewSeen(installed.build);
    return entries;
  }

  Future<void> markWhatsNewSeen(int build) => _settings.set(SettingsRepository.whatsNewSeenBuild, '$build');

  /// This version's notes, for Settings.
  Future<ChangelogEntry?> currentNotes() async => WhatsNew.current(changelog, (await _installed()).build);
}