import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/dates.dart';
import '../../../data/models/category.dart';
import '../../../data/models/payment_card.dart';
import '../../../data/models/transaction_entry.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../import/import_hub_screen.dart';
import 'transaction_form_screen.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final f = ref.read(transactionFilterProvider);
      ref.read(transactionFilterProvider.notifier).set(f.copyWith(search: () => text.trim().isEmpty ? null : text.trim()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionFilterProvider);
    final txs = ref.watch(filteredTransactionsProvider);
    final cards = ref.watch(cardsProvider).asDataOrNull ?? const <PaymentCard>[];
    final cardMap = ref.watch(cardMapProvider).asDataOrNull ?? const <int, PaymentCard>{};
    final categories = ref.watch(categoriesProvider).asDataOrNull ?? const <Category>[];
    final catMap = {for (final c in categories) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Import',
            icon: const Icon(Icons.file_download_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportHubScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search description or notes',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _onSearch('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip('All', filter.cardId == null && !filter.cashOnly,
                    () => _setFilter(filter.copyWith(cardId: () => null, cashOnly: false))),
                _chip('Cash', filter.cashOnly && filter.cardId == null,
                    () => _setFilter(filter.copyWith(cardId: () => null, cashOnly: true))),
                for (final c in cards)
                  _chip('${c.nickname} ••${c.last4}', filter.cardId == c.id,
                      () => _setFilter(filter.copyWith(cardId: () => c.id, cashOnly: false))),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.category_rounded, size: 18),
                    label: Text(filter.categoryId == null ? 'Any category' : (catMap[filter.categoryId]?.name ?? 'Category')),
                    onPressed: () => _pickCategory(categories, filter),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(_rangeLabel(filter)),
                    onPressed: () => _pickRange(filter),
                  ),
                ),
                if (!filter.isEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.filter_alt_off_rounded, size: 18),
                    label: const Text('Clear filters'),
                    onPressed: () {
                      _search.clear();
                      ref.read(transactionFilterProvider.notifier).clear();
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: txs,
              onRetry: () => ref.refreshData(),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: filter.isEmpty ? Icons.receipt_long_rounded : Icons.search_off_rounded,
                    title: filter.isEmpty ? 'No transactions yet' : 'Nothing matches these filters',
                    message: filter.isEmpty ? 'Tap + to add one.' : 'Try clearing a filter.',
                  );
                }
                return _GroupedList(txs: list, categories: catMap, cards: cardMap);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _setFilter(TransactionFilter f) => ref.read(transactionFilterProvider.notifier).set(f);

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  String _rangeLabel(TransactionFilter f) {
    if (f.from == null || f.to == null) return 'Any date';
    final fmt = DateFormat('MMM d');
    final end = f.to!.subtract(const Duration(days: 1));
    return Dates.sameDay(f.from!, end) ? fmt.format(f.from!) : '${fmt.format(f.from!)} – ${fmt.format(end)}';
  }

  Future<void> _pickCategory(List<Category> categories, TransactionFilter filter) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Any category'),
              onTap: () => Navigator.pop(ctx, -1),
            ),
            for (final c in categories)
              ListTile(
                leading: CategoryAvatar(category: c, size: 36),
                title: Text(c.name),
                selected: filter.categoryId == c.id,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _setFilter(filter.copyWith(categoryId: () => picked == -1 ? null : picked));
  }

  Future<void> _pickRange(TransactionFilter filter) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: filter.from != null && filter.to != null
          ? DateTimeRange(start: filter.from!, end: filter.to!.subtract(const Duration(days: 1)))
          : null,
    );
    if (range == null) return;
    _setFilter(filter.copyWith(
      from: () => Dates.startOfDay(range.start),
      to: () => Dates.startOfDay(range.end).add(const Duration(days: 1)),
    ));
  }
}

class _GroupedList extends ConsumerStatefulWidget {
  const _GroupedList({required this.txs, required this.categories, required this.cards});
  final List<TransactionEntry> txs;
  final Map<int?, Category> categories;
  final Map<int, PaymentCard> cards;

  @override
  ConsumerState<_GroupedList> createState() => _GroupedListState();
}

class _GroupedListState extends ConsumerState<_GroupedList> {
  /// Rows swiped away but not yet gone from the provider. A dismissed
  /// Dismissible must leave the tree immediately.
  final _removed = <int>{};

  @override
  Widget build(BuildContext context) {
    final txs = widget.txs.where((t) => !_removed.contains(t.id)).toList();
    final categories = widget.categories;
    final cards = widget.cards;
    // Build "day header" + rows.
    final items = <Object>[];
    String? lastDay;
    for (final t in txs) {
      final key = Dates.dayKey(t.date);
      if (key != lastDay) {
        items.add(t.date);
        lastDay = key;
      }
      items.add(t);
    }
    final dayTotals = <String, int>{};
    for (final t in txs) {
      if (t.isExpense) dayTotals[Dates.dayKey(t.date)] = (dayTotals[Dates.dayKey(t.date)] ?? 0) + t.amount;
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is DateTime) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(child: Text(_dayLabel(item), style: Theme.of(context).textTheme.labelLarge)),
                if ((dayTotals[Dates.dayKey(item)] ?? 0) > 0)
                  AmountText(
                    dayTotals[Dates.dayKey(item)]!,
                    kind: TransactionKind.expense,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
              ],
            ),
          );
        }
        final t = item as TransactionEntry;
        return Dismissible(
          key: ValueKey('tx-${t.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Icon(Icons.delete_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          confirmDismiss: (_) => confirm(context, title: 'Delete transaction?', message: '"${t.description}" will be removed.'),
          onDismissed: (_) async {
            setState(() => _removed.add(t.id!));
            await ref.read(transactionServiceProvider).delete(t.id!);
            ref.refreshData();
            if (context.mounted) showSnack(context, 'Transaction deleted');
          },
          child: TransactionTile(
            tx: t,
            category: categories[t.categoryId],
            card: cards[t.cardId],
            showDate: false,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TransactionFormScreen(existing: t)),
            ),
          ),
        );
      },
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (Dates.sameDay(d, now)) return 'Today';
    if (Dates.sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat(d.year == now.year ? 'EEE, MMM d' : 'EEE, MMM d, yyyy').format(d);
  }
}
