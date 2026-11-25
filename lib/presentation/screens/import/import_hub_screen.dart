import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/feature_flags.dart';
import '../../../data/models/payment_card.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../cards/add_card_onboarding_screen.dart';
import '../cards/cards_screen.dart';
import 'csv_import_screen.dart';
import 'sms_import_screen.dart';

/// Choose a card, then a source to import from.
class ImportHubScreen extends ConsumerStatefulWidget {
  const ImportHubScreen({super.key, this.initialCardId});
  final int? initialCardId;

  @override
  ConsumerState<ImportHubScreen> createState() => _ImportHubScreenState();
}

class _ImportHubScreenState extends ConsumerState<ImportHubScreen> {
  int? _cardId;

  @override
  void initState() {
    super.initState();
    _cardId = widget.initialCardId;
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import transactions'),
        actions: [
          IconButton(
            tooltip: 'How imports work',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddCardOnboardingScreen())),
          ),
        ],
      ),
      body: AsyncView<List<PaymentCard>>(
        value: cards,
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.credit_card_rounded,
              title: 'Add a card first',
              message: 'Imports are saved to a card so you can see what was bought with it.',
              action: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => openAddCard(context, ref),
                child: const Text('Add a card'),
              ),
            );
          }
          final card = list.firstWhere((c) => c.id == _cardId, orElse: () => list.first);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              DropdownButtonFormField<int>(
                initialValue: card.id,
                decoration: const InputDecoration(labelText: 'Card'),
                items: [for (final c in list) DropdownMenuItem(value: c.id, child: Text(c.label))],
                onChanged: (v) => setState(() => _cardId = v),
              ),
              const SizedBox(height: 20),
              _SourceTile(
                icon: Icons.table_view_rounded,
                title: 'CSV statement',
                subtitle: 'Import a statement file from your bank. You map the columns and check every row.',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CsvImportScreen(card: card))),
              ),
              _SourceTile(
                icon: Icons.sms_rounded,
                title: 'SMS alerts',
                subtitle: Platform.isAndroid
                    ? 'Read purchase texts from your bank, on this phone only. Needs your permission.'
                    : 'Only available on Android phones.',
                enabled: Platform.isAndroid,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SmsImportScreen(card: card))),
              ),
              if (FeatureFlags.bankSync)
                const _SourceTile(
                  icon: Icons.sync_rounded,
                  title: 'Bank sync',
                  subtitle: 'Not available yet. See README for how it could be added.',
                  enabled: false,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.icon, required this.title, required this.subtitle, this.onTap, this.enabled = true});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: AppCard(
          onTap: enabled ? onTap : null,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (enabled) const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
