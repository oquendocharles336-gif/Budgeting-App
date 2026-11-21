import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transaction_entry.dart';

/// Optimistic UI: a save shows up in the lists at once, before the database
/// confirms it. Each pending change is dropped once the write finishes
/// (the lists then show the saved row) or fails (the change is rolled back
/// with a message).

// -----------------------------------------------------------------------------
// Transactions
// -----------------------------------------------------------------------------

/// Pending adds (negative temporary ids) and edits (real ids).
class PendingTransactions extends Notifier<Map<int, TransactionEntry>> {
  int _nextTemp = -1;

  @override
  Map<int, TransactionEntry> build() => const {};

  /// Shows a new transaction now. Returns its temporary id.
  int add(TransactionEntry entry) {
    final id = _nextTemp--;
    state = {...state, id: entry.copyWith(id: id)};
    return id;
  }

  /// Shows an edit now. Returns the transaction's id.
  int put(TransactionEntry edited) {
    state = {...state, edited.id!: edited};
    return edited.id!;
  }

  void clear(int id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }
}

final pendingTransactionsProvider =
    NotifierProvider<PendingTransactions, Map<int, TransactionEntry>>(PendingTransactions.new);

/// The same rules as `TransactionRepository.query`, for pending rows.
bool matchesFilter(TransactionEntry t, TransactionFilter f) {
  if (f.cardId != null) {
    if (t.cardId != f.cardId && t.toCardId != f.cardId) return false;
  } else if (f.cashOnly) {
    if (!((t.cardId == null && !t.fromCapital) || (t.isTransfer && t.toCardId == null && !t.toCapital))) return false;
  }
  if (f.categoryId != null && t.categoryId != f.categoryId) return false;
  if (f.kind != null && t.kind != f.kind) return false;
  if (f.from != null && t.date.isBefore(f.from!)) return false;
  if (f.to != null && !t.date.isBefore(f.to!)) return false;
  final q = f.search?.trim().toLowerCase();
  if (q != null && q.isNotEmpty) {
    final inText = t.description.toLowerCase().contains(q) || (t.notes?.toLowerCase().contains(q) ?? false);
    if (!inText) return false;
  }
  return true;
}

/// [base] from the database with the pending changes laid over it, newest
/// first, like the database order.
List<TransactionEntry> withPending(
  List<TransactionEntry> base,
  Map<int, TransactionEntry> pending, {
  bool Function(TransactionEntry t)? matches,
  int? limit,
}) {
  if (pending.isEmpty) return base;
  final seen = <int>{};
  final out = <TransactionEntry>[];
  for (final t in base) {
    final edited = pending[t.id];
    seen.add(t.id!);
    final row = edited ?? t;
    if (matches == null || matches(row)) out.add(row);
  }
  for (final e in pending.entries) {
    if (seen.contains(e.key)) continue;
    if (matches == null || matches(e.value)) out.add(e.value);
  }
  out.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    // Temporary (negative) ids are the newest.
    final ai = a.id! < 0 ? 1 << 40 : a.id!;
    final bi = b.id! < 0 ? 1 << 40 : b.id!;
    return bi.compareTo(ai);
  });
  return limit == null || out.length <= limit ? out : out.sublist(0, limit);
}

// -----------------------------------------------------------------------------
// Budgets
// -----------------------------------------------------------------------------

/// Pending budget amounts by "YYYY-MM|categoryId" (null amount = removed).
class PendingBudgets extends Notifier<Map<String, int?>> {
  @override
  Map<String, int?> build() => const {};

  static String keyFor(String month, int? categoryId) => '$month|${categoryId ?? 'all'}';

  String put(String month, int? categoryId, int? amount) {
    final key = keyFor(month, categoryId);
    state = {...state, key: amount};
    return key;
  }

  void clear(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }
}

final pendingBudgetsProvider = NotifierProvider<PendingBudgets, Map<String, int?>>(PendingBudgets.new);
