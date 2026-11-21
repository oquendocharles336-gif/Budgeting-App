import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/business.dart';

/// Optimistic UI for the business screens: a save shows up
/// at once (keyed by its operation key) and is dropped when the database
/// write finishes (the list then shows the saved row) or fails (rolled back).
class PendingMap<T> extends Notifier<Map<String, T>> {
  @override
  Map<String, T> build() => const {};

  void put(String key, T value) => state = {...state, key: value};

  void clear(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }
}

final pendingOrdersProvider =
    NotifierProvider<PendingMap<BusinessOrder>, Map<String, BusinessOrder>>(PendingMap<BusinessOrder>.new);
final pendingInventoryProvider =
    NotifierProvider<PendingMap<InventoryItem>, Map<String, InventoryItem>>(PendingMap<InventoryItem>.new);
final pendingProductsProvider =
    NotifierProvider<PendingMap<Product>, Map<String, Product>>(PendingMap<Product>.new);
final pendingCapitalProvider =
    NotifierProvider<PendingMap<CapitalEntry>, Map<String, CapitalEntry>>(PendingMap<CapitalEntry>.new);

var _nextTempId = -1;

/// A temporary id for a row that isn't saved yet (always negative).
int tempId() => _nextTempId--;

/// A row shown before its save finished.
bool isUnsaved(int? id) => id == null || id < 0;

/// [base] from the database with pending rows laid over it: edits replace
/// the saved row with the same id, new rows (negative ids) go first.
List<T> overlay<T>(
  List<T> base,
  Iterable<T> pending,
  int? Function(T row) idOf, {
  bool Function(T row)? matches,
}) {
  if (pending.isEmpty) return base;
  final byId = <int, T>{};
  final added = <T>[];
  for (final p in pending) {
    final id = idOf(p);
    if (id == null || id < 0) {
      if (matches == null || matches(p)) added.add(p);
    } else {
      byId[id] = p;
    }
  }
  final out = [...added];
  for (final row in base) {
    final edited = byId[idOf(row)];
    if (edited == null) {
      out.add(row);
    } else if (matches == null || matches(edited)) {
      out.add(edited);
    }
  }
  return out;
}
