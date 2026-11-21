import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// Skip. The app keeps working offline either way.
Future<void> showUpdateSheet(
  BuildContext context, {
  required UpdateCheck check,
  required Future<void> Function(AppVersion version) onSkip,
}) {
  final release = check.release!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    isDismissible: true,
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
              Semantics(header: true, child: Text('Update available', style: text.headlineSmall)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusBadge(label: 'New: ${release.version}', tone: BadgeTone.accent, icon: Icons.system_update_rounded),
                  if (check.installed != null) StatusBadge(label: 'You have ${check.installed!.version}'),
                  if (release.releasedAt != null) StatusBadge(label: DateFormat('MMM d, yyyy').format(release.releasedAt!)),
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
                release.isApk
                    ? 'Your data stays on this phone: installing the update over this app keeps everything. '
                        'After the download, open the file and tap Install (Android may ask you to allow installs from your browser).'
                    : 'This opens the release page on GitHub. Download the APK there and install it over this app; your data stays.',
                style: TextStyle(color: t.onSecondMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _open(ctx, release.downloadUrl),
                icon: Icon(release.isApk ? Icons.download_rounded : Icons.open_in_new_rounded),
                label: Text(release.isApk ? 'Download ${release.version}' : 'Open release page'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  await onSkip(release.version);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Skip this version'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _open(BuildContext ctx, Uri url) async {
  var ok = false;
  try {
    ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && ctx.mounted) {
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (ctx.mounted) showSnack(ctx, 'Couldn\'t open the browser. The download link was copied.');
    return;
  }
  if (ctx.mounted) Navigator.pop(ctx);
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
