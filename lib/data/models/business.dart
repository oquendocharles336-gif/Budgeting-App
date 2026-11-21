/// Business side: capital, inventory (ingredients), products and orders.
/// Money is integer centavos and dates are local time, like the rest of
/// the app.
library;

DateTime? _date(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

// -----------------------------------------------------------------------------
// Capital
// -----------------------------------------------------------------------------

/// Kinds of capital ledger rows.
class CapitalKind {
  CapitalKind._();

  /// + moved in from a personal account.
  static const deposit = 'deposit';

  /// - moved back out to a personal account.
  static const withdrawal = 'withdrawal';

  /// - fee paid out of capital on a withdrawal.
  static const fee = 'fee';

  /// 0: history only. Paid sales went to the personal budget ("Add to
  /// Budget"); they never pass through capital, so the balance is unchanged.
  static const salesAdded = 'sales_added';
}

/// One row of the capital ledger. The capital balance is always the sum of
/// [amount] over all rows.
class CapitalEntry {
  const CapitalEntry({
    this.id,
    required this.amount,
    this.kind = CapitalKind.deposit,
    this.memoAmount,
    this.note,
    required this.date,
    this.transactionId,
    required this.createdAt,
  });

  final int? id;

  /// Signed centavos (+ in, - out).
  final int amount;
  final String kind;

  /// "Sales added" rows: how much went to the personal budget (shown only).
  final int? memoAmount;
  final String? note;
  final DateTime date;

  /// The personal transfer that moved this money (deleting one removes both).
  final int? transactionId;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'kind': kind,
        'memo_amount': memoAmount,
        'note': note,
        'date': date.millisecondsSinceEpoch,
        'transaction_id': transactionId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory CapitalEntry.fromMap(Map<String, Object?> m) => CapitalEntry(
        id: m['id'] as int,
        amount: m['amount'] as int,
        kind: (m['kind'] as String?) ?? CapitalKind.deposit,
        memoAmount: m['memo_amount'] as int?,
        note: m['note'] as String?,
        date: _date(m['date'])!,
        transactionId: m['transaction_id'] as int?,
        createdAt: _date(m['created_at'])!,
      );
}

// -----------------------------------------------------------------------------
// Inventory
// -----------------------------------------------------------------------------

/// Units offered in the picker. Anything else the user types is a custom unit.
const inventoryUnits = ['g', 'kg', 'ml', 'L', 'pcs'];

class InventoryItem {
  const InventoryItem({
    this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    this.lowStock,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;

  /// Current stock: the sum of the item's stock ledger (never typed
  /// directly). Decimal, so "0.5 kg" works.
  final double quantity;
  final String unit;

  /// Warn when [quantity] is at or below this (null = no warning).
  final double? lowStock;

  /// Compressed photo in the app's private folder.
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLow => lowStock != null && quantity <= lowStock!;

  /// "100 g", "1.5 kg", "10 pcs".
  String get quantityLabel => '${formatQuantity(quantity)} $unit';

  InventoryItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    double? Function()? lowStock,
    String? Function()? photoPath,
    DateTime? updatedAt,
  }) =>
      InventoryItem(
        id: id,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        lowStock: lowStock != null ? lowStock() : this.lowStock,
        photoPath: photoPath != null ? photoPath() : this.photoPath,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'low_stock': lowStock,
        'photo_path': photoPath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory InventoryItem.fromMap(Map<String, Object?> m) => InventoryItem(
        id: m['id'] as int,
        name: m['name'] as String,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        unit: m['unit'] as String,
        lowStock: (m['low_stock'] as num?)?.toDouble(),
        photoPath: m['photo_path'] as String?,
        createdAt: _date(m['created_at'])!,
        updatedAt: _date(m['updated_at'])!,
      );
}

/// "100", "1.5", "0.25" (no trailing zeros).
String formatQuantity(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  var s = q.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

enum StockReason {
  restock('restock', 'Restocked'),
  order('order', 'Used in order'),
  adjustment('adjustment', 'Adjusted'),
  orderCancelled('order_cancelled', 'Returned from order');

  const StockReason(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static StockReason fromDb(String? v) =>
      StockReason.values.firstWhere((r) => r.dbValue == v, orElse: () => StockReason.adjustment);
}

/// One row of the stock ledger (+ in, - out).
class StockMovement {
  const StockMovement({
    this.id,
    required this.itemId,
    required this.change,
    required this.reason,
    this.orderId,
    this.note,
    required this.date,
    required this.createdAt,
  });

  final int? id;
  final int itemId;
  final double change;
  final StockReason reason;
  final int? orderId;
  final String? note;
  final DateTime date;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'item_id': itemId,
        'change': change,
        'reason': reason.dbValue,
        'order_id': orderId,
        'note': note,
        'date': date.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory StockMovement.fromMap(Map<String, Object?> m) => StockMovement(
        id: m['id'] as int,
        itemId: m['item_id'] as int,
        change: (m['change'] as num).toDouble(),
        reason: StockReason.fromDb(m['reason'] as String?),
        orderId: m['order_id'] as int?,
        note: m['note'] as String?,
        date: _date(m['date'])!,
        createdAt: _date(m['created_at'])!,
      );
}

/// Recipe line: one unit of the product uses [quantity] of the item.
class RecipeLine {
  const RecipeLine({this.id, this.productId, required this.itemId, required this.quantity, this.itemName, this.unit});

  final int? id;
  final int? productId;
  final int itemId;
  final double quantity;

  /// Joined from the inventory item, for display.
  final String? itemName;
  final String? unit;

  RecipeLine copyWith({double? quantity}) =>
      RecipeLine(id: id, productId: productId, itemId: itemId, quantity: quantity ?? this.quantity, itemName: itemName, unit: unit);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'item_id': itemId,
        'quantity': quantity,
      };

  factory RecipeLine.fromMap(Map<String, Object?> m) => RecipeLine(
        id: m['id'] as int?,
        productId: m['product_id'] as int?,
        itemId: m['item_id'] as int,
        quantity: (m['quantity'] as num).toDouble(),
        itemName: m['item_name'] as String?,
        unit: m['unit'] as String?,
      );
}

// -----------------------------------------------------------------------------
// Products
// -----------------------------------------------------------------------------

class Product {
  const Product({
    this.id,
    required this.name,
    required this.price,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;

  /// Centavos.
  final int price;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product copyWith({String? name, int? price, String? Function()? photoPath, DateTime? updatedAt}) => Product(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        photoPath: photoPath != null ? photoPath() : this.photoPath,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'price': price,
        'photo_path': photoPath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int,
        name: m['name'] as String,
        price: m['price'] as int,
        photoPath: m['photo_path'] as String?,
        createdAt: _date(m['created_at'])!,
        updatedAt: _date(m['updated_at'])!,
      );
}

// -----------------------------------------------------------------------------
// Orders
// -----------------------------------------------------------------------------

enum PaymentMethod {
  cash('cash', 'Cash', null),
  maya('maya', 'Maya (QR)', 'assets/qr/maya.png'),
  maribank('maribank', 'MariBank (QR)', 'assets/qr/maribank.png'),
  bdo('bdo', 'BDO (QR)', 'assets/qr/bdo.png');

  const PaymentMethod(this.dbValue, this.label, this.qrAsset);
  final String dbValue;
  final String label;

  /// QR image shown to the buyer (placeholder until the owner adds theirs).
  final String? qrAsset;

  bool get isCash => this == PaymentMethod.cash;

  static PaymentMethod fromDb(String? v) =>
      PaymentMethod.values.firstWhere((m) => m.dbValue == v, orElse: () => PaymentMethod.cash);
}

/// Complete = the order is done; the buyer may still owe (shown from the
/// amounts). Paid = paid in full (the payment is entered with it).
enum OrderStatus {
  complete('complete', 'Complete'),
  paid('paid', 'Paid');

  const OrderStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  /// Only "Paid" says the buyer has paid in full.
  bool get claimsPaid => this == OrderStatus.paid;

  /// 'delivered' and 'delivered_unpaid' (removed; may still be in an old
  /// backup) read as Complete.
  static OrderStatus fromDb(String? v) => v == 'paid' ? OrderStatus.paid : OrderStatus.complete;
}

class OrderItem {
  const OrderItem({this.id, this.orderId, this.productId, required this.name, required this.unitPrice, required this.quantity});

  final int? id;
  final int? orderId;

  /// Null after the product is deleted (the name and price are kept).
  final int? productId;
  final String name;
  final int unitPrice;
  final int quantity;

  int get lineTotal => unitPrice * quantity;

  OrderItem copyWith({int? quantity}) => OrderItem(
        id: id,
        orderId: orderId,
        productId: productId,
        name: name,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'order_id': orderId,
        'product_id': productId,
        'name': name,
        'unit_price': unitPrice,
        'quantity': quantity,
      };

  factory OrderItem.fromMap(Map<String, Object?> m) => OrderItem(
        id: m['id'] as int?,
        orderId: m['order_id'] as int?,
        productId: m['product_id'] as int?,
        name: m['name'] as String,
        unitPrice: m['unit_price'] as int,
        quantity: m['quantity'] as int,
      );
}

class BusinessOrder {
  const BusinessOrder({
    this.id,
    required this.buyer,
    required this.orderDate,
    required this.items,
    required this.total,
    this.paidAmount = 0,
    this.tendered,
    this.changeGiven,
    this.method = PaymentMethod.cash,
    this.status = OrderStatus.complete,
    this.notes,
    this.budgetTxId,
    this.addedToBudgetAt,
    this.cancelledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String buyer;
  final DateTime orderDate;
  final List<OrderItem> items;

  /// Sum of the items, in centavos.
  final int total;

  /// What the buyer has actually paid so far (never more than [total];
  /// change is given back, not kept).
  final int paidAmount;

  /// Cash handed over at the last cash payment, and the change given.
  final int? tendered;
  final int? changeGiven;
  final PaymentMethod method;
  final OrderStatus status;
  final String? notes;

  /// The personal income transaction this sale was added to (null = not
  /// added yet). Prevents adding the same sale to the budget twice.
  final int? budgetTxId;
  final DateTime? addedToBudgetAt;

  /// Cancelled orders gave their stock back and are left out of sales.
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCancelled => cancelledAt != null;

  int get balanceDue => total - paidAmount < 0 ? 0 : total - paidAmount;
  bool get isFullyPaid => total > 0 && paidAmount >= total;
  bool get isPartiallyPaid => paidAmount > 0 && paidAmount < total;
  bool get addedToBudget => budgetTxId != null;

  /// "2× Ube jam, 1× Cookies"
  String get itemsSummary => items.map((i) => '${i.quantity}× ${i.name}').join(', ');

  static int totalOf(List<OrderItem> items) => items.fold(0, (a, i) => a + i.lineTotal);

  BusinessOrder copyWith({
    int? id,
    String? buyer,
    DateTime? orderDate,
    List<OrderItem>? items,
    int? total,
    int? paidAmount,
    int? Function()? tendered,
    int? Function()? changeGiven,
    PaymentMethod? method,
    OrderStatus? status,
    String? Function()? notes,
    DateTime? updatedAt,
  }) =>
      BusinessOrder(
        id: id ?? this.id,
        buyer: buyer ?? this.buyer,
        orderDate: orderDate ?? this.orderDate,
        items: items ?? this.items,
        total: total ?? this.total,
        paidAmount: paidAmount ?? this.paidAmount,
        tendered: tendered != null ? tendered() : this.tendered,
        changeGiven: changeGiven != null ? changeGiven() : this.changeGiven,
        method: method ?? this.method,
        status: status ?? this.status,
        notes: notes != null ? notes() : this.notes,
        budgetTxId: budgetTxId,
        addedToBudgetAt: addedToBudgetAt,
        cancelledAt: cancelledAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// The `orders` row (items are saved separately).
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'buyer': buyer,
        'order_date': orderDate.millisecondsSinceEpoch,
        'total': total,
        'paid_amount': paidAmount,
        'tendered': tendered,
        'change_given': changeGiven,
        'method': method.dbValue,
        'status': status.dbValue,
        'notes': notes,
        'budget_tx_id': budgetTxId,
        'added_to_budget_at': addedToBudgetAt?.millisecondsSinceEpoch,
        'cancelled_at': cancelledAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory BusinessOrder.fromMap(Map<String, Object?> m, List<OrderItem> items) => BusinessOrder(
        id: m['id'] as int,
        buyer: m['buyer'] as String,
        orderDate: _date(m['order_date'])!,
        items: items,
        total: m['total'] as int,
        paidAmount: (m['paid_amount'] as int?) ?? 0,
        tendered: m['tendered'] as int?,
        changeGiven: m['change_given'] as int?,
        method: PaymentMethod.fromDb(m['method'] as String?),
        status: OrderStatus.fromDb(m['status'] as String?),
        notes: m['notes'] as String?,
        budgetTxId: m['budget_tx_id'] as int?,
        addedToBudgetAt: _date(m['added_to_budget_at']),
        cancelledAt: _date(m['cancelled_at']),
        createdAt: _date(m['created_at'])!,
        updatedAt: _date(m['updated_at'])!,
      );
}
