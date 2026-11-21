import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/budget/budget_calculator.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_card_view.dart';
import '../../widgets/transaction_tile.dart';
import '../import/import_hub_screen.dart';
import '../transactions/transaction_form_screen.dart';
import 'card_form_screen.dart';

/// One card: what was bought with it.
class CardDetailScreen extends ConsumerWidget {
  const CardDetailScreen({super.key, required this.cardId});
  final int cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(cardMapProvider).asDataOrNull?[cardId];
    final txs = ref.watch(cardTransactionsProvider(cardId));
    final cats = ref.watch(categoryMapProvider).asDataOrNull ?? const {};
    final now = DateTime.now();

    if (card == null) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(card.nickname),
        actions: [
          IconButton(
            tooltip: 'Edit card',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardFormScreen(existing: card))),
          ),
        ],
      ),
      body: AsyncView(
        value: txs,
        data: (list) {
          final thisMonth = list.where((t) => t.date.year == now.year && t.date.month == now.month);
          final spent = BudgetCalculator.spent(thisMonth);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(child: PaymentCardView(card: card, width: 320)),
              const SizedBox(height: 16),
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Spent this month'),
                          AmountText(spent, style: Theme.of(context).textTheme.headlineSmall),
                        ],
                      ),
                    ),
                    Text('${list.length} total'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ImportHubScreen(initialCardId: cardId)),
                      ),
                      icon: const Icon(Icons.file_download_rounded),
                      label: const Text('Import'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => TransactionFormScreen(initialCardId: cardId),
                      )),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const SectionHeader('Transactions'),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'Nothing on this card yet',
                  message: 'Add a purchase or import a statement.',
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final t in list)
                        TransactionTile(
                          tx: t,
                          category: cats[t.categoryId],
                          card: card,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => TransactionFormScreen(existing: t)),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
