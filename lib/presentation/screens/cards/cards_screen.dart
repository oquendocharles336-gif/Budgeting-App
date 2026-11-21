import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/payment_card.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_card_view.dart';
import 'add_card_onboarding_screen.dart';
import 'card_detail_screen.dart';
import 'card_form_screen.dart';

/// Opens the onboarding explainer the first time, then the card form.
Future<void> openAddCard(BuildContext context, WidgetRef ref) async {
  final seen = await ref.read(settingsRepositoryProvider).get(SettingsRepository.cardOnboardingSeen);
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => seen == '1' ? const CardFormScreen() : const AddCardOnboardingScreen(),
  ));
}

class CardsScreen extends ConsumerStatefulWidget {
  const CardsScreen({super.key});

  @override
  ConsumerState<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends ConsumerState<CardsScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(cardMapProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cards'),
        actions: [
          IconButton(
            tooltip: 'How card imports work',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddCardOnboardingScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAddCard(context, ref),
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Add card'),
      ),
      body: AsyncView<Map<int, PaymentCard>>(
        value: all,
        data: (map) {
          final active = map.values.where((c) => !c.archived).toList();
          final archived = map.values.where((c) => c.archived).toList();
          if (map.isEmpty) {
            return EmptyState(
              icon: Icons.credit_card_rounded,
              title: 'No cards yet',
              message: 'Add a card to see what you buy with each one. Cash works without a card.',
              action: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => openAddCard(context, ref),
                child: const Text('Add a card'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              for (final c in active) _CardRow(card: c),
              if (archived.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Show archived (${archived.length})'),
                  value: _showArchived,
                  onChanged: (v) => setState(() => _showArchived = v),
                ),
              if (_showArchived) for (final c in archived) _CardRow(card: c),
            ],
          );
        },
      ),
    );
  }
}

class _CardRow extends ConsumerWidget {
  const _CardRow({required this.card});
  final PaymentCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          Opacity(
            opacity: card.archived ? 0.5 : 1,
            child: PaymentCardView(
              card: card,
              width: double.infinity,
              subtitle: card.archived ? 'Archived' : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: card.id!)),
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: PopupMenuButton<String>(
              tooltip: 'Card options',
              iconColor: Colors.white,
              onSelected: (v) => _onMenu(context, ref, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'archive', child: Text(card.archived ? 'Unarchive' : 'Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(cardRepositoryProvider);
    switch (action) {
      case 'edit':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardFormScreen(existing: card)));
      case 'archive':
        await repo.update(card.copyWith(archived: !card.archived));
        ref.refreshData();
      case 'delete':
        final count = await repo.transactionCount(card.id!);
        if (!context.mounted) return;
        final ok = await confirm(
          context,
          title: 'Delete ${card.nickname}?',
          message: count == 0
              ? 'This card has no transactions.'
              : 'This also deletes its $count transaction${count == 1 ? '' : 's'}. '
                  'To keep them, archive the card instead.',
        );
        if (!ok) return;
        await repo.delete(card.id!);
        ref.refreshData();
        if (context.mounted) showSnack(context, 'Card deleted');
    }
  }
}
