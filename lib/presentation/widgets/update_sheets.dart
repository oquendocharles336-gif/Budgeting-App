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
/// Skip. A required update has no Skip, but "Later" still works: the app
/// keeps working offline either way.
Future<void> showUpdateSheet(
  BuildContext context, {
  required UpdateCheck check,
  required Future<void> Function(int build) onSkip,
}) {
  final release = check.release!;
  final mustUpdate = check.urgency == UpdateUrgency.required;
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
              Semantics(
                header: true,
                child: Text(mustUpdate ? 'Update needed' : 'Update available', style: text.headlineSmall),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusBadge(label: 'New: ${release.version}', tone: BadgeTone.accent, icon: Icons.system_update_rounded),
                  StatusBadge(label: 'You have ${check.installed.version}'),
                  if (release.releasedAt != null) StatusBadge(label: DateFormat('MMM d, yyyy').format(release.releasedAt!)),
                ],
              ),
              if (mustUpdate) ...[
                const SizedBox(height: 12),
                Text(
                  'This version is no longer supported. Please update to keep getting fixes.',
                  style: TextStyle(color: t.onSecond, fontWeight: FontWeight.w600),
                ),
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
                'Your data stays on this phone: installing the update over this app keeps everything. '
                'After the download, open the file and tap Install (Android may ask you to allow installs from your browser).',
                style: TextStyle(color: t.onSecondMuted, fontSize: 13),
              ),
              if (release.sha256 != null) ...[
                const SizedBox(height: 8),
                SelectableText('SHA-256: ${release.sha256}', style: TextStyle(color: t.onSecondMuted, fontSize: 11)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await launchUrl(release.apkUrl, mode: LaunchMode.externalApplication);
                  if (!ok && ctx.mounted) {
                    await Clipboard.setData(ClipboardData(text: release.apkUrl.toString()));
                    if (ctx.mounted) showSnack(ctx, 'Couldn\'t open the browser. The download link was copied.');
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.download_rounded),
                label: Text('Download ${release.version}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
              if (!mustUpdate)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    await onSkip(release.build);
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
