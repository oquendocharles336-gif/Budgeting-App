import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../data/models/payment_card.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/motion/swipe_card_deck.dart';
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

/// Cards & e-wallets with their balances, plus Cash. Shown as the
/// "Wallets" tab, and also reachable from Settings.
class CardsScreen extends ConsumerStatefulWidget {
  const CardsScreen({super.key, this.asTab = false});

  /// In the bottom navigation there is already a "+" button, so the add
  /// action moves to the app bar.
  final bool asTab;

  @override
  ConsumerState<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends ConsumerState<CardsScreen> {
  bool _showArchived = false;

  /// Deck order (card ids); a swiped card moves to the back.
  List<int> _order = const [];

  List<PaymentCard> _ordered(List<PaymentCard> active) {
    final byId = {for (final c in active) c.id!: c};
    final order = [
      for (final id in _order)
        if (byId.containsKey(id)) id,
      for (final c in active)
        if (!_order.contains(c.id)) c.id!,
    ];
    _order = order;
    return [for (final id in order) byId[id]!];
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(cardMapProvider);
    final summary = ref.watch(balanceSummaryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cards & e-wallets'),
        actions: [
          IconButton(
            tooltip: 'How card imports work',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddCardOnboardingScreen()),
            ),
          ),
          if (widget.asTab)
            IconButton(
              tooltip: 'Add card or e-wallet',
              icon: const Icon(Icons.add_card_rounded),
              onPressed: () => openAddCard(context, ref),
            ),
        ],
      ),
      floatingActionButton: widget.asTab
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openAddCard(context, ref),
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Add account'),
            ),
      body: AsyncView<Map<int, PaymentCard>>(
        value: all,
        onRetry: () => ref.refreshData(),
        data: (map) {
          final active = map.values.where((c) => !c.archived).toList();
          final archived = map.values.where((c) => c.archived).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              AsyncView<BalanceSummary>(
                value: summary,
                loading: const SkeletonCard(height: 120),
                data: (b) => _TotalCard(summary: b),
              ),
              const SizedBox(height: 12),
              const _CashTile(),
              const SizedBox(height: 16),
              if (map.isEmpty)
                EmptyState(
                  icon: Icons.credit_card_rounded,
                  title: 'No cards or e-wallets yet',
                  message: 'Add a bank card, GCash or Maya with how much is in it. '
                      'Expenses you pay with it are taken from that balance.',
                  action: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => openAddCard(context, ref),
                    child: const Text('Add card or e-wallet'),
                  ),
                ),
              if (active.isNotEmpty) ...[
                SwipeCardDeck<PaymentCard>(
                  items: _ordered(active),
                  keyOf: (c) => c.id!,
                  onSwiped: (c) => setState(() => _order = [..._order.where((id) => id != c.id), c.id!]),
                  onTap: (c) => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: c.id!)),
                  ),
                  itemBuilder: (context, c) => PaymentCardView(
                    card: c,
                    width: double.infinity,
                    subtitle: '${c.balanceLabel}: ${formatMoney(ref, c.balance)}',
                  ),
                ),
                const SizedBox(height: 12),
                _DeckActions(card: _ordered(active).first, count: active.length),
                const SizedBox(height: 12),
              ],
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

class _TotalCard extends ConsumerWidget {
  const _TotalCard({required this.summary});
  final BalanceSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available balance', style: TextStyle(color: scheme.onSurfaceVariant)),
          AmountText(
            summary.available,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: summary.available < 0 ? scheme.error : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary.hasCredit
                ? 'Cash, bank and e-wallets. Plus ${formatMoney(ref, summary.availableCredit)} available credit.'
                : 'Cash, bank and e-wallets together.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Cash is always there and can't be deleted; only its amount is edited.
class _CashTile extends ConsumerWidget {
  const _CashTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cash = ref.watch(cashBalanceProvider);
    final scheme = Theme.of(context).colorScheme;
    final value = cash.asDataOrNull ?? 0;
    return AppCard(
      onTap: () => editBalance(context, ref, accountId: null, name: 'Cash', current: value),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.payments_rounded, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('Money in your pocket', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          AmountText(
            value,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: value < 0 ? scheme.error : null),
          ),
          const SizedBox(width: 4),
          Icon(Icons.edit_rounded, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Lets the user type the real amount in an account ([accountId] null = Cash).
Future<void> editBalance(
  BuildContext context,
  WidgetRef ref, {
  required int? accountId,
  required String name,
  required int current,
  bool isCredit = false,
}) async {
  final value = await showDialog<int>(
    context: context,
    builder: (_) => _BalanceDialog(
      title: isCredit ? 'Available credit on $name' : '$name balance',
      initial: current < 0 ? 0 : current,
      symbol: ref.read(currencyProvider).symbol,
    ),
  );
  if (value == null) return;
  try {
    await ref.read(cardRepositoryProvider).setBalance(accountId, value);
    ref.refreshData();
    if (context.mounted) showSnack(context, '$name balance updated');
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not update balance: $e', error: true);
  }
}

class _BalanceDialog extends StatefulWidget {
  const _BalanceDialog({required this.title, required this.initial, required this.symbol});
  final String title;
  final int initial;
  final String symbol;

  @override
  State<_BalanceDialog> createState() => _BalanceDialogState();
}

class _BalanceDialogState extends State<_BalanceDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: Money.toInput(widget.initial));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(Money.parse(_controller.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(labelText: 'Amount now', prefixText: '${widget.symbol} '),
            validator: (v) => validateAmount(v, allowZero: true),
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: _submit,
            child: const Text('Save'),
          ),
        ],
      );
}

/// Actions for the card on top of the deck.
class _DeckActions extends ConsumerWidget {
  const _DeckActions({required this.card, required this.count});
  final PaymentCard card;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (count > 1)
          Text(
            'Swipe the card to see your other $count accounts',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _cardAction(context, ref, card, 'balance'),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Edit balance'),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'More for ${card.nickname}',
              onSelected: (v) => _cardAction(context, ref, card, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                PopupMenuItem(value: 'archive', child: Text(card.archived ? 'Unarchive' : 'Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ],
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
              subtitle: '${card.archived ? 'Archived · ' : ''}${card.balanceLabel}: ${formatMoney(ref, card.balance)}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: card.id!)),
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: PopupMenuButton<String>(
              tooltip: 'Account options',
              // Same rule as the card's own text: readable on its color.
              iconColor: AppTheme.onColor(Color(card.color)),
              onSelected: (v) => _cardAction(context, ref, card, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'balance', child: Text('Edit balance')),
                const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                PopupMenuItem(value: 'archive', child: Text(card.archived ? 'Unarchive' : 'Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _cardAction(BuildContext context, WidgetRef ref, PaymentCard card, String action) async {
    final repo = ref.read(cardRepositoryProvider);
    switch (action) {
      case 'balance':
        await editBalance(
          context,
          ref,
          accountId: card.id,
          name: card.nickname,
          current: card.balance,
          isCredit: card.isCredit,
        );
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
              ? 'This account has no transactions.'
              : 'This also deletes its $count transaction${count == 1 ? '' : 's'}. Transfers with other '
                  'accounts are undone there too. To keep them, archive it instead.',
        );
        if (!ok) return;
        try {
          await repo.delete(card.id!);
        } catch (e) {
          if (context.mounted) showSnack(context, 'Could not delete: $e', error: true);
          return;
        }
        ref.refreshData();
        if (context.mounted) showSnack(context, '${card.nickname} deleted');
    }
  }
