import 'transaction_entry.dart';

/// A transaction as produced by a [TransactionSource], before it is
/// normalized, categorized, de-duplicated and saved.
class RawTransaction {
  const RawTransaction({
    required this.date,
    required this.description,
    required this.amount,
    this.kind = TransactionKind.expense,
    required this.source,
    this.cardId,
    this.externalId,
    this.categoryId,
    this.notes,
    this.originalText,
  });

  final DateTime date;
  final String description;

  /// Positive centavos.
  final int amount;
  final TransactionKind kind;
  final TransactionSourceType source;

  /// null = cash.
  final int? cardId;

  /// Stable ID from the source (SMS id, statement reference, bank txn id).
  final String? externalId;

  /// Set when the user already chose a category (manual entry).
  final int? categoryId;
  final String? notes;

  /// The CSV row or SMS text, shown in review screens.
  final String? originalText;

  RawTransaction copyWith({
    DateTime? date,
    String? description,
    int? amount,
    TransactionKind? kind,
    int? Function()? cardId,
    int? Function()? categoryId,
  }) =>
      RawTransaction(
        date: date ?? this.date,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        kind: kind ?? this.kind,
        source: source,
        cardId: cardId != null ? cardId() : this.cardId,
        externalId: externalId,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        notes: notes,
        originalText: originalText,
      );
}
