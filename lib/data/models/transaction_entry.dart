/// Whether money went out (expense) or came in (income/refund/payment).
enum TransactionKind {
  expense,
  income;

  static TransactionKind fromDb(String v) =>
      v == 'income' ? TransactionKind.income : TransactionKind.expense;
}

/// Where a transaction came from. Stored in the `source` column.
enum TransactionSourceType {
  manual('manual', 'Manual'),
  csvImport('csv_import', 'CSV import'),
  smsParsed('sms_parsed', 'SMS'),
  bankSync('bank_sync', 'Bank sync');

  const TransactionSourceType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static TransactionSourceType fromDb(String v) => TransactionSourceType.values
      .firstWhere((s) => s.dbValue == v, orElse: () => TransactionSourceType.manual);
}

/// One saved transaction. Named `TransactionEntry` to avoid clashing with
/// sqflite's `Transaction` class.
class TransactionEntry {
  const TransactionEntry({
    this.id,
    required this.amount,
    required this.kind,
    required this.description,
    this.categoryId,
    this.cardId,
    required this.date,
    this.notes,
    this.source = TransactionSourceType.manual,
    this.externalId,
    this.dedupHash,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;

  /// Always positive, in centavos. Direction is given by [kind].
  final int amount;
  final TransactionKind kind;
  final String description;
  final int? categoryId;

  /// null means a cash transaction.
  final int? cardId;
  final DateTime date;
  final String? notes;
  final TransactionSourceType source;
  final String? externalId;
  final String? dedupHash;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCash => cardId == null;
  bool get isExpense => kind == TransactionKind.expense;

  /// Signed amount: negative for expenses.
  int get signedAmount => isExpense ? -amount : amount;

  TransactionEntry copyWith({
    int? id,
    int? amount,
    TransactionKind? kind,
    String? description,
    int? Function()? categoryId,
    int? Function()? cardId,
    DateTime? date,
    String? Function()? notes,
    TransactionSourceType? source,
    String? Function()? externalId,
    String? Function()? dedupHash,
    DateTime? updatedAt,
  }) =>
      TransactionEntry(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        kind: kind ?? this.kind,
        description: description ?? this.description,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        cardId: cardId != null ? cardId() : this.cardId,
        date: date ?? this.date,
        notes: notes != null ? notes() : this.notes,
        source: source ?? this.source,
        externalId: externalId != null ? externalId() : this.externalId,
        dedupHash: dedupHash != null ? dedupHash() : this.dedupHash,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'kind': kind.name,
        'description': description,
        'category_id': categoryId,
        'card_id': cardId,
        'date': date.millisecondsSinceEpoch,
        'notes': notes,
        'source': source.dbValue,
        'external_id': externalId,
        'dedup_hash': dedupHash,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory TransactionEntry.fromMap(Map<String, Object?> m) => TransactionEntry(
        id: m['id'] as int,
        amount: m['amount'] as int,
        kind: TransactionKind.fromDb(m['kind'] as String),
        description: m['description'] as String,
        categoryId: m['category_id'] as int?,
        cardId: m['card_id'] as int?,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        notes: m['notes'] as String?,
        source: TransactionSourceType.fromDb(m['source'] as String),
        externalId: m['external_id'] as String?,
        dedupHash: m['dedup_hash'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}

/// Filters for the transaction list.
class TransactionFilter {
  const TransactionFilter({
    this.cardId,
    this.cashOnly = false,
    this.categoryId,
    this.from,
    this.to,
    this.search,
    this.kind,
  });

  /// Only transactions on this card.
  final int? cardId;

  /// Only cash transactions (ignored when [cardId] is set).
  final bool cashOnly;
  final int? categoryId;

  /// Inclusive start.
  final DateTime? from;

  /// Exclusive end.
  final DateTime? to;
  final String? search;
  final TransactionKind? kind;

  bool get isEmpty =>
      cardId == null &&
      !cashOnly &&
      categoryId == null &&
      from == null &&
      to == null &&
      (search == null || search!.isEmpty) &&
      kind == null;

  TransactionFilter copyWith({
    int? Function()? cardId,
    bool? cashOnly,
    int? Function()? categoryId,
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? Function()? search,
    TransactionKind? Function()? kind,
  }) =>
      TransactionFilter(
        cardId: cardId != null ? cardId() : this.cardId,
        cashOnly: cashOnly ?? this.cashOnly,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        search: search != null ? search() : this.search,
        kind: kind != null ? kind() : this.kind,
      );
}
