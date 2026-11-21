/// A purchase made now and paid later (e.g. "Shoes via SPayLater").
///
/// It is NOT counted as spending while unpaid. Marking it paid creates one
/// real expense ([expenseTxId]) on the day it was paid, so the money is
/// counted exactly once.
enum PayLaterStatus {
  unpaid,
  paid;

  static PayLaterStatus fromDb(String? v) => v == 'paid' ? PayLaterStatus.paid : PayLaterStatus.unpaid;

  String get label => this == PayLaterStatus.paid ? 'Paid' : 'Unpaid';
}

class PayLaterItem {
  const PayLaterItem({
    this.id,
    required this.item,
    required this.amount,
    this.categoryId,
    required this.purchaseDate,
    required this.dueDate,
    this.status = PayLaterStatus.unpaid,
    this.paidAt,
    this.expenseTxId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;

  /// What was bought, e.g. "Rice cooker".
  final String item;

  /// Positive centavos.
  final int amount;
  final int? categoryId;
  final DateTime purchaseDate;
  final DateTime dueDate;
  final PayLaterStatus status;
  final DateTime? paidAt;

  /// The expense created when it was marked paid.
  final int? expenseTxId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPaid => status == PayLaterStatus.paid;

  PayLaterItem copyWith({
    int? id,
    String? item,
    int? amount,
    int? Function()? categoryId,
    DateTime? purchaseDate,
    DateTime? dueDate,
    PayLaterStatus? status,
    DateTime? Function()? paidAt,
    int? Function()? expenseTxId,
    String? Function()? notes,
    DateTime? updatedAt,
  }) =>
      PayLaterItem(
        id: id ?? this.id,
        item: item ?? this.item,
        amount: amount ?? this.amount,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        dueDate: dueDate ?? this.dueDate,
        status: status ?? this.status,
        paidAt: paidAt != null ? paidAt() : this.paidAt,
        expenseTxId: expenseTxId != null ? expenseTxId() : this.expenseTxId,
        notes: notes != null ? notes() : this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'item': item,
        'amount': amount,
        'category_id': categoryId,
        'purchase_date': purchaseDate.millisecondsSinceEpoch,
        'due_date': dueDate.millisecondsSinceEpoch,
        'status': status.name,
        'paid_at': paidAt?.millisecondsSinceEpoch,
        'expense_tx_id': expenseTxId,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory PayLaterItem.fromMap(Map<String, Object?> m) {
    DateTime? date(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
    return PayLaterItem(
      id: m['id'] as int,
      item: m['item'] as String,
      amount: m['amount'] as int,
      categoryId: m['category_id'] as int?,
      purchaseDate: date(m['purchase_date'])!,
      dueDate: date(m['due_date'])!,
      status: PayLaterStatus.fromDb(m['status'] as String?),
      paidAt: date(m['paid_at']),
      expenseTxId: m['expense_tx_id'] as int?,
      notes: m['notes'] as String?,
      createdAt: date(m['created_at'])!,
      updatedAt: date(m['updated_at'])!,
    );
  }
}
