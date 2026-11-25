import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/services/phone_access_service.dart';
import '../providers/core_providers.dart';
import '../providers/data_providers.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// What each access is for, in the user's words.
({IconData icon, String title, String why}) phoneAccessInfo(PhoneAccess access) => switch (access) {
      PhoneAccess.notifications => (
          icon: Icons.notifications_active_rounded,
          title: 'Notifications',
          why: 'Budget alerts and debt reminders',
        ),
      PhoneAccess.sms => (
          icon: Icons.sms_rounded,
          title: 'Read bank texts',
          why: 'Only for Import from SMS. Optional',
        ),
      PhoneAccess.installUpdates => (
          icon: Icons.system_update_rounded,
          title: 'Install updates',
          why: 'Lets Pitaka install its own updates ("Install unknown apps")',
        ),
    };

/// Asks for [access] (system question first, then the settings page) and
/// refreshes the status everywhere. Returns whether it is allowed now.
Future<bool> allowPhoneAccess(BuildContext context, WidgetRef ref, PhoneAccess access) async {
  final service = ref.read(phoneAccessServiceProvider);
  bool allowed;
  try {
    allowed = await service.allow(access);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t open the phone\'s settings: $e', error: true);
    return false;
  }
  ref.invalidate(phoneAccessProvider);
  if (!context.mounted) return allowed;
  final title = phoneAccessInfo(access).title;
  showSnack(
    context,
    allowed ? '$title allowed' : '$title still not allowed. You can allow it any time in Settings > Phone permissions.',
    error: !allowed,
  );
  return allowed;
}

/// Settings > "Phone permissions": every access with its status and an
/// "Allow" button when it's missing.
class PhoneAccessSection extends ConsumerWidget {
  const PhoneAccessSection({super.key, this.showInstall = true});

  /// Off where updates can't be installed from inside the app.
  final bool showInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(phoneAccessServiceProvider);
    if (!service.supported) return const SizedBox.shrink();
    final status = ref.watch(phoneAccessProvider).asDataOrNull;
    return Card(
      child: Column(
        children: [
          for (final access in [
            PhoneAccess.notifications,
            PhoneAccess.sms,
            if (showInstall) PhoneAccess.installUpdates,
          ])
            _AccessTile(access: access, allowed: status?.allows(access)),
        ],
      ),
    );
  }
}

class _AccessTile extends ConsumerStatefulWidget {
  const _AccessTile({required this.access, required this.allowed});
  final PhoneAccess access;

  /// Null while loading.
  final bool? allowed;

  @override
  ConsumerState<_AccessTile> createState() => _AccessTileState();
}

class _AccessTileState extends ConsumerState<_AccessTile> {
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    await allowPhoneAccess(context, ref, widget.access);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = phoneAccessInfo(widget.access);
    final scheme = Theme.of(context).colorScheme;
    final allowed = widget.allowed;
    final opensSettings = ref.read(phoneAccessServiceProvider).opensSettings(widget.access);
    Widget trailing;
    if (allowed == null) {
      trailing = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (allowed) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: StatusColors.ok(context), size: 20),
          const SizedBox(width: 4),
          Text('Allowed', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ],
      );
    } else {
      trailing = FilledButton.tonal(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
        onPressed: _busy ? null : _allow,
        child: Text(opensSettings ? 'Open settings' : 'Allow'),
      );
    }
    return ListTile(
      leading: Icon(info.icon),
      title: Text(info.title),
      subtitle: Text(info.why),
      trailing: trailing,
    );
  }
}

/// Home: a card with an "Allow" button for each thing the phone hasn't
/// allowed yet that Pitaka needs (notifications; SMS only if the user
/// turned SMS import on before). "Not now" hides it for a week. Nothing
/// is shown when everything is allowed.
class PhoneAccessCard extends ConsumerWidget {
  const PhoneAccessCard({super.key});

  static const snooze = Duration(days: 7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(phoneAccessServiceProvider).supported) return const SizedBox.shrink();
    final status = ref.watch(phoneAccessProvider).asDataOrNull;
    final needs = ref.watch(phoneAccessNeedsProvider).asDataOrNull;
    if (status == null || needs == null) return const SizedBox.shrink();
    final until = needs.snoozedUntil;
    if (until != null && DateTime.now().isBefore(until)) return const SizedBox.shrink();
    final missing = [
      if (!status.notifications) PhoneAccess.notifications,
      if (needs.smsInUse && !status.sms) PhoneAccess.sms,
    ];
    if (missing.isEmpty) return const SizedBox.shrink();

    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phonelink_setup_rounded, color: t.accentOnSecond),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Pitaka needs your OK', style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your phone hasn\'t allowed these yet. Nothing leaves your phone.',
              style: TextStyle(color: t.onSecondMuted, fontSize: 13),
            ),
            for (final access in missing) _MissingRow(access: access),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final until = DateTime.now().add(snooze).millisecondsSinceEpoch;
                  await ref.read(settingsRepositoryProvider).set(SettingsRepository.phoneAccessSnoozedUntil, '$until');
                  ref.invalidate(phoneAccessNeedsProvider);
                },
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingRow extends ConsumerStatefulWidget {
  const _MissingRow({required this.access});
  final PhoneAccess access;

  @override
  ConsumerState<_MissingRow> createState() => _MissingRowState();
}

class _MissingRowState extends ConsumerState<_MissingRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final info = phoneAccessInfo(widget.access);
    final t = context.tokens;
    final opensSettings = ref.read(phoneAccessServiceProvider).opensSettings(widget.access);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(info.icon, color: t.onSecondMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(info.why, style: TextStyle(color: t.onSecondMuted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await allowPhoneAccess(context, ref, widget.access);
                    if (mounted) setState(() => _busy = false);
                  },
            child: Text(opensSettings ? 'Open settings' : 'Allow'),
          ),
        ],
      ),
    );
  }
}
