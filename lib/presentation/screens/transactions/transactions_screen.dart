import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/dates.dart';
import '../../../data/models/category.dart';
import '../../../data/models/payment_card.dart';
import '../../../data/models/transaction_entry.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/activity_row.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/animated_icons.dart';
import '../../widgets/motion/cascade.dart';
import '../import/import_hub_screen.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  /// The search field slides open from the app bar icon (magnifier <-> X).
  bool _searchOpen = false;

  /// Filter chips row, shown/hidden from the app bar (menu <-> X).
  bool _filtersOpen = true;

  @override
  void initState() {
    super.initState();
    // Coming back with a search still active: keep the field open.
    final active = ref.read(transactionFilterProvider).search;
    if (active != null) {
      _searchOpen = true;
      _search.text = active;
    }
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchFocus.requestFocus();
    } else {
      _searchFocus.unfocus();
      if (_search.text.isNotEmpty) {
        _search.clear();
        _onSearch('');
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
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
            tooltip: _searchOpen ? 'Close search' : 'Search',
            onPressed: _toggleSearch,
            icon: AnimatedSearchIcon(open: _searchOpen),
          ),
          IconButton(
            tooltip: _filtersOpen ? 'Hide filters' : 'Show filters',
            onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            icon: AnimatedMenuIcon(open: _filtersOpen),
          ),
          IconButton(
            tooltip: 'Import',
            icon: const Icon(Icons.file_download_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportHubScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: Cascade.reduced(context) ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: !_searchOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
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
          ),
          AnimatedSize(
            duration: Cascade.reduced(context) ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: !_filtersOpen
                ? const SizedBox(width: double.infinity)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                  _chip(c.shortLabel, filter.cardId == c.id,
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
  /// Rows deleted but not yet gone from the provider (hidden at once).
  final _removed = <int>{};

  /// Which row floats (tap) or shows Edit / Delete (swipe right).
  final _selection = ActivitySelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

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
      if (t.isExpense && !t.isLoanCancelledByRepayment) dayTotals[Dates.dayKey(t.date)] = (dayTotals[Dates.dayKey(t.date)] ?? 0) + t.amount;
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is DateTime) {
          return CascadeIn(
            index: i,
            child: Padding(
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
          ),
          );
        }
        final t = item as TransactionEntry;
        return CascadeIn(
          key: ValueKey('row-${t.id}'),
          index: i,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ActivityRow(
              tx: t,
              selection: _selection,
              category: categories[t.categoryId],
              card: cards[t.cardId],
              toCard: cards[t.toCardId],
              showDate: false,
              onDeleted: () {
                if (mounted) setState(() => _removed.add(t.id!));
              },
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
