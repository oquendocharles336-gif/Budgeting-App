import '../models/payment_card.dart';
import '../models/raw_transaction.dart';
import '../models/transaction_entry.dart';
import 'transaction_source.dart';

/// PLACEHOLDER — not functional.
///
/// Real bank/card linking needs a licensed aggregator (for example Brankas
/// or Finverse in the Philippines) and a small backend that holds the
/// aggregator's secret keys. See README > "Adding bank sync later".
///
/// Hidden in the UI unless FeatureFlags.bankSync is true.
class BankSyncSource implements TransactionSource {
  const BankSyncSource();

  @override
  String get id => TransactionSourceType.bankSync.dbValue;

  @override
  String get displayName => 'Bank sync (coming later)';

  @override
  bool get requiresNetwork => true;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<RawTransaction>> fetchTransactions({
    required PaymentCard card,
    DateTime? since,
  }) async {
    throw const SourceUnavailableException('Bank sync is not available yet.');
  }
}
