import '../models/payment_card.dart';
import '../models/raw_transaction.dart';

/// Anything that can produce card transactions: manual entry, a CSV
/// statement, SMS alerts, or (later) a bank-sync aggregator.
///
/// Sources only *produce* [RawTransaction]s. They never touch the database.
/// `TransactionImportService` normalizes, categorizes, de-duplicates and
/// saves them, so adding a new source needs no UI, database or budget changes.
abstract class TransactionSource {
  /// Stable ID, e.g. "csv_import". Matches TransactionSourceType.dbValue.
  String get id;

  /// Shown to the user, e.g. "CSV statement".
  String get displayName;

  /// True if the source needs the internet (only bank sync).
  bool get requiresNetwork;

  /// Whether the source can be used right now on this device.
  Future<bool> isAvailable();

  /// Transactions for [card], optionally only those on/after [since].
  Future<List<RawTransaction>> fetchTransactions({
    required PaymentCard card,
    DateTime? since,
  });
}

/// Thrown when a source can't be used (no permission, not implemented...).
class SourceUnavailableException implements Exception {
  const SourceUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}
