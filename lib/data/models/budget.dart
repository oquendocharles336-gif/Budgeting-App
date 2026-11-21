/// A budget amount for one month. [categoryId] null = the overall budget.
class Budget {
  const Budget({
    this.id,
    required this.month,
    this.categoryId,
    required this.amount,
  });

  final int? id;

  /// "YYYY-MM"
  final String month;
  final int? categoryId;

  /// Centavos.
  final int amount;

  bool get isOverall => categoryId == null;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'month': month,
        'category_id': categoryId,
        'amount': amount,
      };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int,
        month: m['month'] as String,
        categoryId: m['category_id'] as int?,
        amount: m['amount'] as int,
      );
}
