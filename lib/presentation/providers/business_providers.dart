import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/business.dart';
import '../../domain/business/capital_math.dart';
import '../../domain/business/sales_analytics.dart';
import 'core_providers.dart';
import 'pending_providers.dart';

// Like data_providers.dart: every provider watches dataRevisionProvider,
// so `ref.refreshData()` after a write reloads the business screens too.
// Saves still in progress (pending_providers.dart) are laid on top.

final _capitalBaseProvider = FutureProvider<List<CapitalEntry>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(capitalRepositoryProvider).all();
});

/// The capital ledger, newest first.
final capitalEntriesProvider = FutureProvider<List<CapitalEntry>>((ref) async {
  final base = await ref.watch(_capitalBaseProvider.future);
  return overlay(base, ref.watch(pendingCapitalProvider).values, (e) => e.id);
});

/// Always the sum of the ledger (including deposits/withdrawals being saved).
final capitalBalanceProvider = FutureProvider<int>((ref) async => CapitalMath.balance(await ref.watch(capitalEntriesProvider.future)));

final _inventoryBaseProvider = FutureProvider.family<List<InventoryItem>, String>((ref, search) {
  ref.watch(dataRevisionProvider);
  return ref.watch(inventoryRepositoryProvider).all(search: search);
});

/// Search text -> inventory items (stock from the ledger).
final inventoryProvider = FutureProvider.family<List<InventoryItem>, String>((ref, search) async {
  final base = await ref.watch(_inventoryBaseProvider(search).future);
  final q = search.trim().toLowerCase();
  return overlay(
    base,
    ref.watch(pendingInventoryProvider).values,
    (i) => i.id,
    matches: (i) => q.isEmpty || i.name.toLowerCase().contains(q),
  );
});

final stockHistoryProvider = FutureProvider.family<List<StockMovement>, int>((ref, itemId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(inventoryRepositoryProvider).movements(itemId);
});

final _productsBaseProvider = FutureProvider<List<Product>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(productRepositoryProvider).all();
});

final productsProvider = FutureProvider<List<Product>>((ref) async {
  final base = await ref.watch(_productsBaseProvider.future);
  return overlay(base, ref.watch(pendingProductsProvider).values, (p) => p.id);
});

final recipeProvider = FutureProvider.family<List<RecipeLine>, int>((ref, productId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(productRepositoryProvider).recipe(productId);
});

typedef OrderQuery = ({String search, OrderStatus? status});

final _ordersBaseProvider = FutureProvider.family<List<BusinessOrder>, OrderQuery>((ref, q) {
  ref.watch(dataRevisionProvider);
  return ref.watch(orderRepositoryProvider).all(search: q.search, status: q.status);
});

final ordersProvider = FutureProvider.family<List<BusinessOrder>, OrderQuery>((ref, q) async {
  final base = await ref.watch(_ordersBaseProvider(q).future);
  final search = q.search.trim().toLowerCase();
  return overlay(
    base,
    ref.watch(pendingOrdersProvider).values,
    (o) => o.id,
    matches: (o) => (search.isEmpty || o.buyer.toLowerCase().contains(search)) && (q.status == null || o.status == q.status),
  );
});

/// Cleaned orders (the shared data-prep step) and their numbers.
class SalesData {
  const SalesData({required this.prepared, required this.summary});
  final PreparedOrders prepared;
  final SalesSummary summary;

  List<BusinessOrder> get orders => prepared.orders;
}

final salesDataProvider = FutureProvider<SalesData>((ref) async {
  ref.watch(dataRevisionProvider);
  final raw = await ref.watch(orderRepositoryProvider).raw();
  // Cancelled orders aren't sales.
  final prepared = BusinessDataPrep.clean(raw.orders.where((r) => r['cancelled_at'] == null), raw.items);
  return SalesData(prepared: prepared, summary: SalesAnalytics.summarize(prepared.orders));
});

/// The owner's uploaded payment QR (encrypted photo path) for a method,
/// or null when none is set up yet.
final paymentQrPathProvider = FutureProvider.family<String?, PaymentMethod>((ref, method) {
  ref.watch(dataRevisionProvider);
  if (!method.usesQr) return Future.value(null);
  return ref.watch(photoServiceProvider).paymentQrPath(method.dbValue);
});
