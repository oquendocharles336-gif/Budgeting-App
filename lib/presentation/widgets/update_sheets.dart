import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/sources/apk_updater.dart';
import '../../data/sources/phone_access.dart';
import '../../domain/services/app_lock_service.dart';
import '../../domain/services/update_service.dart';
import '../theme/app_palette.dart';
import 'common.dart';
import 'status_badge.dart';

/// Bullet list of release notes (plain text only; never HTML or links).
class _Notes extends StatelessWidget {
  const _Notes(this.notes);
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.check_rounded, size: 18, color: t.accentOnSecond))),
                const SizedBox(width: 10),
                Expanded(child: Text(n, style: TextStyle(color: t.onSecond))),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Update available": the new version, its notes, and Download / Later /
/// Skip. On Android, Download fetches the APK inside the app (with progress)
/// and opens Android's own "Update Pitaka?" screen: no browser. Elsewhere, or
/// when the release has no APK, it opens the release page instead.
Future<void> showUpdateSheet(
  BuildContext context, {
  required UpdateCheck check,
  required Future<void> Function(AppVersion version) onSkip,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Not dismissible by a tap outside while downloading (see _UpdateSheet).
    isDismissible: true,
    builder: (ctx) => _UpdateSheet(check: check, onSkip: onSkip),
  );
}

enum _Step { ready, downloading, installing, failed }

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.check, required this.onSkip});
  final UpdateCheck check;
  final Future<void> Function(AppVersion version) onSkip;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  _Step _step = _Step.ready;
  int _received = 0;
  int? _total;
  String? _error;
  DownloadCancel? _cancel;

  /// Android refused to install because "Install unknown apps" is off for
  /// Pitaka: the sheet shows an "Allow" button for it.
  bool _needsInstallAccess = false;

  ReleaseInfo get _release => widget.check.release!;
  bool get _inApp => ApkUpdater.supported && _release.isApk;
  bool get _busy => _step == _Step.downloading || _step == _Step.installing;

  @override
  void dispose() {
    // Closing the sheet (or the app locking) stops a running download.
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    if (!_inApp) {
      await _openInBrowser();
      return;
    }
    final cancel = DownloadCancel();
    setState(() {
      _step = _Step.downloading;
      _received = 0;
      _total = _release.apkSize;
      _error = null;
      _cancel = cancel;
      _needsInstallAccess = false;
    });
    try {
      final apk = await ApkUpdater.download(
        _release.downloadUrl,
        version: '${_release.version}',
        expectedSize: _release.apkSize,
        expectedSha256: _release.apkSha256,
        cancel: cancel,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _step = _Step.installing);
      // Android's installer (and, the first time, its "Install unknown apps"
      // switch) is another screen: don't lock the app while it's up.
      final outcome = await LockGuard.run(() => ApkUpdater.install(apk));
      if (!mounted) return;
      switch (outcome) {
        case InstallOutcome.installed:
          Navigator.pop(context);
        case InstallOutcome.cancelled:
          setState(() => _step = _Step.ready);
          showSnack(context, 'Update not installed. Tap Update when you\'re ready.');
        case InstallOutcome.permissionDenied:
          _fail('Pitaka needs your OK to install updates. Tap Allow, turn on "Allow from this source", then come back.');
          setState(() => _needsInstallAccess = true);
        case InstallOutcome.failed:
          _fail('Android couldn\'t install the update. If this keeps happening, the update may be signed with a '
              'different key than the app on this phone.');
      }
    } on ApkUpdateException catch (e) {
      if (!mounted) return;
      if (cancel.isCancelled) {
        setState(() => _step = _Step.ready);
      } else {
        _fail(e.message);
      }
    } catch (e) {
      if (mounted) _fail('Could not update: $e');
    }
  }

  /// Opens Android's "Install unknown apps" page for Pitaka; when the user
  /// comes back with it allowed, the update starts again by itself.
  Future<void> _allowInstall() async {
    PhoneAccessStatus after;
    try {
      after = await LockGuard.run(() => const PhoneAccessChannel().openSettings(PhoneAccess.installUpdates));
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t open the phone\'s settings: $e', error: true);
      return;
    }
    if (!mounted) return;
    if (after.installUpdates) {
      await _download();
    } else {
      showSnack(context, 'Installing updates is still not allowed.', error: true);
    }
  }

  void _fail(String message) => setState(() {
        _step = _Step.failed;
        _error = message;
      });

  Future<void> _openInBrowser() async {
    final url = _release.isApk ? _release.downloadUrl : _release.pageUrl;
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: url.toString()));
      if (mounted) showSnack(context, 'Couldn\'t open the browser. The download link was copied.');
      return;
    }
    Navigator.pop(context);
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final release = _release;
    final check = widget.check;
    final progress = _total == null || _total == 0 ? null : (_received / _total!).clamp(0.0, 1.0).toDouble();
    return PopScope(
      // Back doesn't close the sheet mid-download by accident; Cancel does.
      canPop: !_busy,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Semantics(header: true, child: Text('Update available', style: text.headlineSmall)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusBadge(label: 'New: ${release.version}', tone: BadgeTone.accent, icon: Icons.system_update_rounded),
                  if (check.installed != null) StatusBadge(label: 'You have ${check.installed!.version}'),
                  if (release.releasedAt != null) StatusBadge(label: DateFormat('MMM d, yyyy').format(release.releasedAt!)),
                  if (release.apkSize != null) StatusBadge(label: '${_mb(release.apkSize!)} MB'),
                ],
              ),
              if (release.name != null && release.name != release.tag) ...[
                const SizedBox(height: 12),
                Text(release.name!, style: text.titleMedium?.copyWith(color: t.onSecond)),
              ],
              const SizedBox(height: 16),
              Text('What\'s new', style: text.titleMedium),
              const SizedBox(height: 8),
              if (release.notes.isEmpty)
                Text('Fixes and improvements.', style: TextStyle(color: t.onSecond))
              else
                _Notes(release.notes),
              const SizedBox(height: 8),
              Text(
                _inApp
                    ? 'The update downloads here, then Android asks you to confirm. Your data stays on this phone. '
                        'The first time, Android asks you to allow Pitaka to install apps.'
                    : 'This opens the release page on GitHub. Download the APK there and install it over this app; your data stays.',
                style: TextStyle(color: t.onSecondMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (_step == _Step.downloading) ...[
                Semantics(
                  liveRegion: true,
                  label: progress == null ? 'Downloading' : 'Downloading, ${(progress * 100).round()} percent',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: progress, minHeight: 10),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress == null
                      ? 'Downloading… ${_mb(_received)} MB'
                      : 'Downloading… ${(progress * 100).round()}% · ${_mb(_received)} of ${_mb(_total!)} MB',
                  style: TextStyle(color: t.onSecond),
                ),
                const SizedBox(height: 4),
                Text('Keep Pitaka open until it finishes.', style: TextStyle(color: t.onSecondMuted, fontSize: 13)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => _cancel?.cancel(), child: const Text('Cancel download')),
              ] else if (_step == _Step.installing) ...[
                const LinearProgressIndicator(minHeight: 10),
                const SizedBox(height: 8),
                Text('Opening the installer… Tap Update on Android\'s screen.', style: TextStyle(color: t.onSecond)),
              ] else ...[
                if (_step == _Step.failed && _error != null) ...[
                  Text(_error!, style: TextStyle(color: t.danger, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                ],
                if (_step == _Step.failed && _needsInstallAccess) ...[
                  FilledButton.icon(
                    onPressed: _allowInstall,
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Allow'),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: _download,
                  icon: Icon(_inApp ? Icons.system_update_alt_rounded : Icons.open_in_new_rounded),
                  label: Text(
                    _step == _Step.failed
                        ? 'Try again'
                        : (_inApp ? 'Download ${release.version}' : 'Open release page'),
                  ),
                ),
                if (_step == _Step.failed && _inApp)
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _openInBrowser,
                    child: const Text('Download in the browser instead'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    await widget.onSkip(release.version);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Skip this version'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Result of "Check now" that isn't "update available": up to date, or
/// what went wrong (no internet, rate limit, no releases...) with Retry.
Future<void> showUpdateResultDialog(BuildContext context, UpdateCheck check, {VoidCallback? onRetry}) {
  final upToDate = check.status == UpdateStatus.upToDate;
  final (IconData icon, String title) = upToDate
      ? (Icons.verified_rounded, 'You\'re up to date')
      : switch (check.errorKind) {
          UpdateErrorKind.offline || UpdateErrorKind.timeout => (Icons.wifi_off_rounded, 'No connection'),
          UpdateErrorKind.rateLimited => (Icons.hourglass_top_rounded, 'Too many checks'),
          UpdateErrorKind.noReleases => (Icons.inventory_2_outlined, 'No releases found'),
          _ => (Icons.error_outline_rounded, 'Couldn\'t check for updates'),
        };
  final message = upToDate
      ? 'Pitaka ${check.installed?.version ?? ''} is the newest version'
          '${check.release == null ? '' : ' (latest release: ${check.release!.tag})'}.'
      : check.errorMessage ?? 'Something went wrong.';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon),
      title: Text(title),
      content: Text(message),
      actions: [
        if (!upToDate && onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onRetry();
            },
            child: const Text('Try again'),
          ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// "What's new" after updating (built into the app, so it works offline).
Future<void> showWhatsNewSheet(BuildContext context, List<ChangelogEntry> entries) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final t = ctx.tokens;
        final text = Theme.of(ctx).textTheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Semantics(header: true, child: Text('What\'s new', style: text.headlineSmall)),
                for (final e in entries) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Version ${e.version}${e.date == null ? '' : ' · ${e.date}'}',
                    style: text.titleMedium?.copyWith(color: t.onSecond),
                  ),
                  const SizedBox(height: 8),
                  _Notes(e.notes),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
              ],
            ),
          ),
        );
      },
    );
