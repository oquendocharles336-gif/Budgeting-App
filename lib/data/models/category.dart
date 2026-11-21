import 'transaction_entry.dart';

/// Built-in categories the app treats specially. Stored in `categories.role`.
enum CategoryRole {
  /// "Other" / "Other income": the user types their own label.
  other,

  /// "Borrowed money": saving this income also adds a debt.
  loan,

  /// "Debt": the expense category for new debts.
  debt;

  static CategoryRole? fromDb(String? v) {
    for (final r in CategoryRole.values) {
      if (r.name == v) return r;
    }
    return null;
  }
}

class Category {
  const Category({
    this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.isDefault = false,
    this.sortOrder = 0,
    this.kind = TransactionKind.expense,
    this.role,
  });

  final int? id;
  final String name;

  /// Key into the app's icon map (see `category_icons.dart`).
  final String icon;

  /// ARGB color value.
  final int color;
  final bool isDefault;
  final int sortOrder;

  /// Expense or income. Budgets and spending charts only use expense ones.
  final TransactionKind kind;
  final CategoryRole? role;

  bool get isIncome => kind == TransactionKind.income;
  bool get isOther => role == CategoryRole.other;
  bool get isLoan => role == CategoryRole.loan;
  bool get isDebt => role == CategoryRole.debt;

  Category copyWith({String? name, String? icon, int? color, int? sortOrder, TransactionKind? kind}) => Category(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        isDefault: isDefault,
        sortOrder: sortOrder ?? this.sortOrder,
        kind: kind ?? this.kind,
        role: role,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'is_default': isDefault ? 1 : 0,
        'sort_order': sortOrder,
        'kind': kind == TransactionKind.income ? 'income' : 'expense',
        'role': role?.name,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as String,
        color: m['color'] as int,
        isDefault: (m['is_default'] as int? ?? 0) == 1,
        sortOrder: m['sort_order'] as int? ?? 0,
        kind: (m['kind'] as String?) == 'income' ? TransactionKind.income : TransactionKind.expense,
        role: CategoryRole.fromDb(m['role'] as String?),
      );
}

/// "If the description contains [keyword], use [categoryId]."
class CategoryRule {
  const CategoryRule({
    this.id,
    required this.keyword,
    required this.categoryId,
    this.priority = 0,
  });

  final int? id;
  final String keyword;
  final int categoryId;

  /// Higher wins when several rules match.
  final int priority;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'keyword': keyword,
        'category_id': categoryId,
        'priority': priority,
      };

  factory CategoryRule.fromMap(Map<String, Object?> m) => CategoryRule(
        id: m['id'] as int,
        keyword: m['keyword'] as String,
        categoryId: m['category_id'] as int,
        priority: m['priority'] as int? ?? 0,
      );
}
