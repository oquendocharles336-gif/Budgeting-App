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
    this.toCardId,
    this.externalId,
    this.categoryId,
    this.customCategory,
    this.notes,
    this.originalText,
    this.savingsAction,
  });

  final DateTime date;
  final String description;

  /// Positive centavos.
  final int amount;
  final TransactionKind kind;
  final TransactionSourceType source;

  /// null = cash.
  final int? cardId;

  /// Transfers only: destination account (null = cash).
  final int? toCardId;

  /// Stable ID from the source (SMS id, statement reference, bank txn id).
  final String? externalId;

  /// Set when the user already chose a category (manual entry).
  final int? categoryId;

  /// Typed label for an "Other" category.
  final String? customCategory;
  final String? notes;

  /// The CSV row or SMS text, shown in review screens.
  final String? originalText;

  /// Savings deposit vs withdrawal.
  final SavingsAction? savingsAction;

  RawTransaction copyWith({
    DateTime? date,
    String? description,
    int? amount,
    TransactionKind? kind,
    int? Function()? cardId,
    int? Function()? categoryId,
    SavingsAction? savingsAction,
  }) =>
      RawTransaction(
        date: date ?? this.date,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        kind: kind ?? this.kind,
        source: source,
        cardId: cardId != null ? cardId() : this.cardId,
        toCardId: toCardId,
        externalId: externalId,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        customCategory: customCategory,
        notes: notes,
        originalText: originalText,
        savingsAction: savingsAction ?? this.savingsAction,
      );
}
