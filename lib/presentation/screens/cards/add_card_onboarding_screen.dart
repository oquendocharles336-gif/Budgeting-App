import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/feature_flags.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../providers/core_providers.dart';
import 'card_form_screen.dart';

/// Explains, in plain language, how card transactions get into the app.
class AddCardOnboardingScreen extends ConsumerWidget {
  const AddCardOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Adding a card')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Text('How your card purchases get here', style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'You only save a nickname and the last 4 digits. Never your full card number, CVV or bank password.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  const _Option(
                    icon: Icons.edit_note_rounded,
                    title: 'Type them in',
                    body: 'Tap + after you buy something and pick the card you used. Quick and always works.',
                  ),
                  const _Option(
                    icon: Icons.table_view_rounded,
                    title: 'Import your statement (CSV)',
                    body: 'Download your card statement as a CSV file from your bank\'s website or app, then import it. '
                        'You choose which columns are the date, description and amount, and check everything before saving. '
                        'Already-imported items are skipped.',
                  ),
                  _Option(
                    icon: Icons.sms_rounded,
                    title: 'Read SMS alerts${Platform.isAndroid ? '' : ' (Android only)'}',
                    body: 'If your bank texts you after each purchase, the app can read those texts on your phone and '
                        'turn them into transactions for you to review. It\'s off until you allow it, and texts never '
                        'leave your phone.',
                  ),
                  if (Platform.isAndroid)
                    const _Option(
                      icon: Icons.notifications_active_rounded,
                      title: 'Connect App Notifications (Free)',
                      badge: 'New',
                      body: 'For Maya, GCash, MariBank or BDO Pay: turn on "Track payments automatically" when you add '
                          'the account, then allow Notification access. When the app shows a payment, Pitaka records '
                          'it and takes it from that balance. Free, offline, and only that app\'s notifications are read.',
                    ),
                  _Option(
                    icon: Icons.sync_rounded,
                    title: 'Automatic bank sync',
                    badge: FeatureFlags.bankSync ? 'Preview' : 'Not available',
                    body: 'Linking directly to your bank needs an internet connection, a licensed partner company and an '
                        'account. That would break this app\'s promise to stay offline with no sign-up, so it isn\'t '
                        'included. It may come later as an optional extra.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: () async {
                  await ref.read(settingsRepositoryProvider).set(SettingsRepository.cardOnboardingSeen, '1');
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CardFormScreen()));
                },
                child: const Text('Add my card'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.body, this.badge});
  final IconData icon;
  final String title;
  final String body;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(badge!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
