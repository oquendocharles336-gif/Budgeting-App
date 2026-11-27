import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/business.dart';
import '../models/transaction_entry.dart';
import 'account_ledger.dart';
import 'linked_records.dart';
import 'op_guard.dart';

String _like(String s) => '%${s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
String _marks(int n) => List.filled(n, '?').join(',');
const _chunk = 400;

// -----------------------------------------------------------------------------
// Capital
// -----------------------------------------------------------------------------

class CapitalRepository {
  CapitalRepository(this._db);
  final Database _db;

  /// Newest first.
  Future<List<CapitalEntry>> all() async {
    final rows = await _db.query('capital_entries', orderBy: 'date DESC, id DESC');
    return rows.map(CapitalEntry.fromMap).toList();
  }

  /// The sum of the ledger.
  Future<int> balance() => balanceIn(_db);

  static Future<int> balanceIn(DatabaseExecutor db) async {
    final r = await db.rawQuery('SELECT IFNULL(SUM(amount), 0) AS s FROM capital_entries');
    return (r.first['s'] as int?) ?? 0;
  }

  /// For [TransactionRepository.insertTransfer]'s `afterInsert`, so the
  /// transfer and its capital rows are saved together.
  static Future<int> insertInTxn(DatabaseExecutor txn, CapitalEntry e) =>
      txn.insert('capital_entries', e.toMap()..remove('id'));

  /// Deletes the entry. One made by a transfer deletes that transfer too
  /// (with its fee and every capital row it made), so the money goes back.
  Future<void> delete(CapitalEntry e) => _db.transaction((txn) async {
        final txId = e.transactionId;
        if (txId != null) {
          final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [txId], limit: 1);
          if (rows.isNotEmpty) {
            await LinkedRecords.beforeTransactionsDeleted(txn, [txId]);
            await AccountLedger.apply(txn, TransactionEntry.fromMap(rows.first), sign: -1);
            await txn.delete('transactions', where: 'id = ?', whereArgs: [txId]);
          }
        }
        await txn.delete('capital_entries', where: 'id = ?', whereArgs: [e.id]);
      });
}

// -----------------------------------------------------------------------------
// Inventory + stock ledger
// -----------------------------------------------------------------------------

class InventoryRepository {
  InventoryRepository(this._db);
  final Database _db;

  /// Stock is always computed from the ledger, never read from a stored number.
  static const _select = '''
    SELECT i.id, i.name, i.unit, i.low_stock, i.photo_path, i.created_at, i.updated_at,
           IFNULL((SELECT SUM(m.change) FROM stock_movements m WHERE m.item_id = i.id), 0) AS stock
    FROM inventory_items i''';

  static InventoryItem _fromRow(Map<String, Object?> r) => InventoryItem.fromMap({...r, 'quantity': r['stock']});

  /// Low-stock items first, then by name. [search] matches the name.
  Future<List<InventoryItem>> all({String? search}) async {
    final q = search?.trim();
    final hasQ = q != null && q.isNotEmpty;
    final rows = await _db.rawQuery(
      '$_select ${hasQ ? "WHERE i.name LIKE ? ESCAPE '\\'" : ''} '
      'ORDER BY (i.low_stock IS NOT NULL AND stock <= i.low_stock) DESC, i.name COLLATE NOCASE',
      hasQ ? [_like(q)] : null,
    );
    return rows.map(_fromRow).toList();
  }

  Future<InventoryItem?> byId(int id) async {
    final rows = await _db.rawQuery('$_select WHERE i.id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Current stock per item (ledger sums), inside a transaction.
  static Future<Map<int, double>> stockIn(DatabaseExecutor db, Iterable<int> itemIds) async {
    final ids = itemIds.toSet().toList();
    final out = <int, double>{};
    for (var i = 0; i < ids.length; i += _chunk) {
      final part = ids.sublist(i, math.min(i + _chunk, ids.length));
      final rows = await db.rawQuery(
        'SELECT item_id, SUM(change) AS s FROM stock_movements WHERE item_id IN (${_marks(part.length)}) GROUP BY item_id',
        part,
      );
      for (final r in rows) {
        out[r['item_id'] as int] = (r['s'] as num?)?.toDouble() ?? 0;
      }
    }
    return out;
  }

  static Future<void> addMovements(DatabaseExecutor db, Iterable<StockMovement> rows) async {
    for (final m in rows) {
      await db.insert('stock_movements', m.toMap()..remove('id'));
    }
  }

  /// Saves a new item and its starting stock as the first ledger row.
  Future<int> insert(InventoryItem i, {String? opKey}) => _db.transaction((txn) => OpGuard.once(txn, opKey, () async {
        final map = i.toMap()
          ..remove('id')
          ..['quantity'] = 0; // Legacy column; stock lives in the ledger.
        final id = await txn.insert('inventory_items', map);
        if (i.quantity > 0) {
          await txn.insert('stock_movements', {
            'item_id': id,
            'change': i.quantity,
            'reason': StockReason.adjustment.dbValue,
            'note': 'Starting stock',
            'date': i.createdAt.millisecondsSinceEpoch,
            'created_at': i.createdAt.millisecondsSinceEpoch,
          });
        }
        return id;
      }));

  /// Saves name, unit, warning level and photo. A changed quantity becomes
  /// an "adjustment" ledger row from [adjustment] (it gets the current stock).
  Future<void> update(InventoryItem i, {StockMovement? Function(double currentStock)? adjustment}) =>
      _db.transaction((txn) async {
        final map = i.toMap()
          ..remove('quantity')
          ..remove('created_at');
        await txn.update('inventory_items', map, where: 'id = ?', whereArgs: [i.id]);
        if (adjustment != null) {
          final current = (await stockIn(txn, [i.id!]))[i.id!] ?? 0;
          final row = adjustment(current);
          if (row != null) await txn.insert('stock_movements', row.toMap()..remove('id'));
        }
      });

  /// Adds a "restock" row. Each [opKey] adds once, so a retry or double tap
  /// doesn't restock twice.
  Future<void> restock(int id, double amount, {String? opKey, String? note}) =>
      _db.transaction((txn) => OpGuard.once(txn, opKey, () async {
            final now = DateTime.now().millisecondsSinceEpoch;
            return txn.insert('stock_movements', {
              'item_id': id,
              'change': amount,
              'reason': StockReason.restock.dbValue,
              'note': note,
              'date': now,
              'created_at': now,
            });
          }));

  /// Stock history, newest first.
  Future<List<StockMovement>> movements(int itemId) async {
    final rows = await _db.query('stock_movements', where: 'item_id = ?', whereArgs: [itemId], orderBy: 'date DESC, id DESC');
    return rows.map(StockMovement.fromMap).toList();
  }

  /// The item, its ledger and recipe lines (ON DELETE CASCADE).
  Future<void> delete(int id) async {
    await _db.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> photoPaths() async {
    final rows = await _db.query('inventory_items', columns: ['photo_path'], where: 'photo_path IS NOT NULL');
    return [for (final r in rows) r['photo_path'] as String];
  }

  /// (id, path) of every item with a photo, for the photo encryption step.
  Future<List<(int, String)>> photoRows() async {
    final rows = await _db.query('inventory_items', columns: ['id', 'photo_path'], where: 'photo_path IS NOT NULL');
    return [for (final r in rows) (r['id'] as int, r['photo_path'] as String)];
  }

  Future<void> setPhotoPath(int id, String? path) async {
    await _db.update('inventory_items', {'photo_path': path}, where: 'id = ?', whereArgs: [id]);
  }
}

// -----------------------------------------------------------------------------
// Products + recipes
// -----------------------------------------------------------------------------

class ProductRepository {
  ProductRepository(this._db);
  final Database _db;

  Future<List<Product>> all({String? search}) async {
    final q = search?.trim();
    final rows = await _db.query(
      'products',
      where: q == null || q.isEmpty ? null : "name LIKE ? ESCAPE '\\'",
      whereArgs: q == null || q.isEmpty ? null : [_like(q)],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Saves a product and its recipe. Each [opKey] inserts once.
  Future<int> insert(Product p, {List<RecipeLine> recipe = const [], String? opKey}) =>
      _db.transaction((txn) => OpGuard.once(txn, opKey, () async {
            final id = await txn.insert('products', p.toMap()..remove('id'));
            await _writeRecipe(txn, id, recipe);
            return id;
          }));

  /// Saves the product and replaces its recipe (affects future orders only).
  Future<void> update(Product p, {List<RecipeLine>? recipe}) => _db.transaction((txn) async {
        await txn.update('products', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
        if (recipe != null) await _writeRecipe(txn, p.id!, recipe);
      });

  static Future<void> _writeRecipe(DatabaseExecutor txn, int productId, List<RecipeLine> recipe) async {
    await txn.delete('product_ingredients', where: 'product_id = ?', whereArgs: [productId]);
    final seen = <int>{};
    for (final line in recipe) {
      if (line.quantity <= 0 || !seen.add(line.itemId)) continue;
      await txn.insert('product_ingredients', {'product_id': productId, 'item_id': line.itemId, 'quantity': line.quantity});
    }
  }

  Future<List<RecipeLine>> recipe(int productId) async => (await recipesIn(_db, [productId]))[productId] ?? const [];

  /// product id -> recipe lines (with the ingredient's name and unit).
  static Future<Map<int, List<RecipeLine>>> recipesIn(DatabaseExecutor db, Iterable<int> productIds) async {
    final ids = productIds.toSet().toList();
    final out = <int, List<RecipeLine>>{};
    for (var i = 0; i < ids.length; i += _chunk) {
      final part = ids.sublist(i, math.min(i + _chunk, ids.length));
      final rows = await db.rawQuery('''
        SELECT p.id, p.product_id, p.item_id, p.quantity, i.name AS item_name, i.unit
        FROM product_ingredients p JOIN inventory_items i ON i.id = p.item_id
        WHERE p.product_id IN (${_marks(part.length)}) ORDER BY p.id''', part);
      for (final r in rows) {
        out.putIfAbsent(r['product_id'] as int, () => []).add(RecipeLine.fromMap(r));
      }
    }
    return out;
  }

  /// Old orders keep the product's name and price (order_items copy them).
  Future<void> delete(int id) async {
    await _db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> photoPaths() async {
    final rows = await _db.query('products', columns: ['photo_path'], where: 'photo_path IS NOT NULL');
    return [for (final r in rows) r['photo_path'] as String];
  }

  Future<List<(int, String)>> photoRows() async {
    final rows = await _db.query('products', columns: ['id', 'photo_path'], where: 'photo_path IS NOT NULL');
    return [for (final r in rows) (r['id'] as int, r['photo_path'] as String)];
  }

  Future<void> setPhotoPath(int id, String? path) async {
    await _db.update('products', {'photo_path': path}, where: 'id = ?', whereArgs: [id]);
  }
}

// -----------------------------------------------------------------------------
// Orders
// -----------------------------------------------------------------------------

/// What the stock step needs to plan an order's ledger rows. Gathered by
/// the repository inside the save's SQLite transaction; planned by the
/// domain layer (`StockPlan`).
class OrderStockContext {
  const OrderStockContext({
    required this.orderId,
    required this.items,
    required this.recipes,
    required this.currentNet,
    required this.stock,
    required this.cancelled,
  });

  final int orderId;
  final List<OrderItem> items;
  final Map<int, List<RecipeLine>> recipes;

  /// Sum of the order's existing ledger rows per item (zero or negative).
  final Map<int, double> currentNet;

  /// Current stock per involved item.
  final Map<int, double> stock;
  final bool cancelled;
}

/// Plans the ledger rows for an order (may throw to cancel the save).
typedef StockPlanner = List<StockMovement> Function(OrderStockContext ctx);

/// Result of [OrderRepository.addToBudget].
typedef AddToBudgetResult = ({int? transactionId, int orders, int amount});

class OrderRepository {
  OrderRepository(this._db);
  final Database _db;

  /// Newest first. [search] matches the buyer's name; [status] filters.
  Future<List<BusinessOrder>> all({String? search, OrderStatus? status}) async {
    final where = <String>[];
    final args = <Object?>[];
    final q = search?.trim();
    if (q != null && q.isNotEmpty) {
      where.add("buyer LIKE ? ESCAPE '\\'");
      args.add(_like(q));
    }
    // Payment status follows the amounts (see OrderStatus).
    if (status != null) where.add(status.sqlWhere);
    final rows = await _db.query(
      'orders',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'order_date DESC, id DESC',
    );
    final items = await _itemsFor(_db, [for (final r in rows) r['id'] as int]);
    return [for (final r in rows) BusinessOrder.fromMap(r, items[r['id']] ?? const [])];
  }

  Future<BusinessOrder?> byId(int id) => _byId(_db, id);

  static Future<BusinessOrder?> _byId(DatabaseExecutor db, int id) async {
    final rows = await db.query('orders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final items = await _itemsFor(db, [id]);
    return BusinessOrder.fromMap(rows.first, items[id] ?? const []);
  }

  static Future<Map<int, List<OrderItem>>> _itemsFor(DatabaseExecutor db, List<int> ids) async {
    final out = <int, List<OrderItem>>{};
    for (var i = 0; i < ids.length; i += _chunk) {
      final part = ids.sublist(i, math.min(i + _chunk, ids.length));
      final rows = await db.query('order_items', where: 'order_id IN (${_marks(part.length)})', whereArgs: part, orderBy: 'id');
      for (final r in rows) {
        out.putIfAbsent(r['order_id'] as int, () => []).add(OrderItem.fromMap(r));
      }
    }
    return out;
  }

  /// Raw rows for the sales cleaning step (orders and their items).
  Future<({List<Map<String, Object?>> orders, List<Map<String, Object?>> items})> raw() async {
    final orders = await _db.query('orders', orderBy: 'order_date DESC, id DESC');
    final items = await _db.query('order_items', orderBy: 'id');
    return (orders: orders, items: items);
  }

  /// What ingredients a not-yet-saved order would use, against stock
  /// (and what [orderId] already holds, when editing). For the warning
  /// shown before saving.
  Future<OrderStockContext> stockContext(List<OrderItem> items, {int? orderId}) =>
      _stockContext(_db, orderId ?? -1, items, cancelled: false);

  static Future<OrderStockContext> _stockContext(
    DatabaseExecutor db,
    int orderId,
    List<OrderItem> items, {
    required bool cancelled,
  }) async {
    final recipes = await ProductRepository.recipesIn(db, items.map((i) => i.productId).whereType<int>());
    final net = <int, double>{};
    if (orderId > 0) {
      final rows = await db.rawQuery(
        'SELECT item_id, SUM(change) AS s FROM stock_movements WHERE order_id = ? GROUP BY item_id',
        [orderId],
      );
      for (final r in rows) {
        net[r['item_id'] as int] = (r['s'] as num?)?.toDouble() ?? 0;
      }
    }
    final itemIds = {...net.keys, for (final lines in recipes.values) for (final l in lines) l.itemId};
    final stock = await InventoryRepository.stockIn(db, itemIds);
    return OrderStockContext(orderId: orderId, items: items, recipes: recipes, currentNet: net, stock: stock, cancelled: cancelled);
  }

  /// Saves the order, replaces its items and updates the stock ledger
  /// through [planStock], all in one SQLite transaction (a throw from the
  /// planner, e.g. "not enough stock", saves nothing). Each [opKey] saves
  /// once. The "added to budget" link is never changed here.
  Future<int> save(BusinessOrder o, {required StockPlanner planStock, String? opKey}) =>
      _db.transaction((txn) => OpGuard.once(txn, opKey, () async {
            final map = o.toMap()
              ..remove('budget_tx_id')
              ..remove('added_to_budget_at')
              ..remove('cancelled_at');
            final int id;
            if (o.id == null) {
              id = await txn.insert('orders', map..remove('id'));
            } else {
              id = o.id!;
              await txn.update('orders', map, where: 'id = ?', whereArgs: [id]);
              await txn.delete('order_items', where: 'order_id = ?', whereArgs: [id]);
            }
            for (final item in o.items) {
              final row = item.toMap()
                ..remove('id')
                ..['order_id'] = id;
              await txn.insert('order_items', row);
            }
            final current = await txn.query('orders', columns: ['cancelled_at'], where: 'id = ?', whereArgs: [id]);
            final cancelled = current.isNotEmpty && current.first['cancelled_at'] != null;
            final ctx = await _stockContext(txn, id, o.items, cancelled: cancelled);
            await InventoryRepository.addMovements(txn, planStock(ctx));
            return id;
          }));

  /// Payment, method, status and notes only. Never touches items or stock,
  /// so paying or changing status can't use ingredients again.
  Future<void> saveHeader(BusinessOrder o, {String? opKey}) =>
      _db.transaction((txn) => OpGuard.once(txn, opKey, () async {
            await txn.update(
              'orders',
              {
                'buyer': o.buyer,
                'order_date': o.orderDate.millisecondsSinceEpoch,
                'paid_amount': o.paidAmount,
                'tendered': o.tendered,
                'change_given': o.changeGiven,
                'method': o.method.dbValue,
                'status': o.status.dbValue,
                'fulfillment': o.fulfillment.dbValue,
                'notes': o.notes,
                'updated_at': o.updatedAt.millisecondsSinceEpoch,
              },
              where: 'id = ?',
              whereArgs: [o.id],
            );
            return o.id!;
          }));

  Future<void> setStatus(int id, OrderStatus status) async {
    await _db.update(
      'orders',
      {'status': status.dbValue, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delivered / For Pick-up / Pending. Never touches payment or stock.
  Future<void> setFulfillment(int id, FulfillmentStatus fulfillment) async {
    await _db.update(
      'orders',
      {'fulfillment': fulfillment.dbValue, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks the order cancelled and gives its stock back ([planStock] gets
  /// `cancelled: true` and returns reversing rows).
  Future<void> cancel(int id, {required StockPlanner planStock, String? opKey}) =>
      _db.transaction((txn) => OpGuard.once(txn, opKey, () async {
            final order = await _byId(txn, id);
            if (order == null || order.isCancelled) return id;
            await txn.update('orders', {'cancelled_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
            final ctx = await _stockContext(txn, id, order.items, cancelled: true);
            await InventoryRepository.addMovements(txn, planStock(ctx));
            return id;
          }));

  /// Deletes the order after giving its stock back. A sale already added
  /// to the budget keeps its income transaction.
  Future<void> delete(int id, {required StockPlanner planStock}) => _db.transaction((txn) async {
        final order = await _byId(txn, id);
        if (order == null) return;
        final ctx = await _stockContext(txn, id, order.items, cancelled: true);
        await InventoryRepository.addMovements(txn, planStock(ctx));
        await txn.delete('orders', where: 'id = ?', whereArgs: [id]);
      });

  /// Adds paid sales to the personal budget as one income transaction,
  /// flags each order and adds a "sales added" row to the capital history
  /// (amount 0: the money goes to the personal side, not through capital).
  /// Eligibility is decided inside the transaction, so a second press adds
  /// nothing. Cancelled orders never qualify.
  Future<AddToBudgetResult> addToBudget({
    Set<int>? onlyIds,
    required List<BusinessOrder> Function(List<BusinessOrder> orders) eligible,
    required TransactionEntry Function(List<BusinessOrder> orders) incomeFor,
  }) =>
      _db.transaction((txn) async {
        final rows = await txn.query('orders', where: 'budget_tx_id IS NULL AND cancelled_at IS NULL', orderBy: 'order_date, id');
        final items = await _itemsFor(txn, [for (final r in rows) r['id'] as int]);
        var candidates = [for (final r in rows) BusinessOrder.fromMap(r, items[r['id']] ?? const [])];
        if (onlyIds != null) candidates = candidates.where((o) => onlyIds.contains(o.id)).toList();
        final chosen = eligible(candidates);
        if (chosen.isEmpty) return (transactionId: null, orders: 0, amount: 0);
        final income = incomeFor(chosen);
        final txId = await txn.insert('transactions', income.toMap()..remove('id'));
        await AccountLedger.apply(txn, income);
        final now = DateTime.now().millisecondsSinceEpoch;
        var flagged = 0;
        for (final o in chosen) {
          flagged += await txn.update(
            'orders',
            {'budget_tx_id': txId, 'added_to_budget_at': now},
            where: 'id = ? AND budget_tx_id IS NULL',
            whereArgs: [o.id],
          );
        }
        if (flagged != chosen.length) throw StateError('Orders changed while adding to the budget');
        await CapitalRepository.insertInTxn(
          txn,
          CapitalEntry(
            amount: 0,
            kind: CapitalKind.salesAdded,
            memoAmount: income.amount,
            note: '${chosen.length} paid sale${chosen.length == 1 ? '' : 's'} added to the personal budget',
            date: income.date,
            transactionId: txId,
            createdAt: income.createdAt,
          ),
        );
        return (transactionId: txId, orders: chosen.length, amount: income.amount);
      });
}
