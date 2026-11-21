import '../models/payment_card.dart';
import '../models/raw_transaction.dart';
import '../models/transaction_entry.dart';
import 'transaction_source.dart';

/// The user types transactions in.
///
/// The add/edit form builds a [RawTransaction] and hands it to
/// `TransactionImportService.saveManual`, which runs the same pipeline as
/// every other source. [stage] + [fetchTransactions] exist so manual entry
/// also fits the common interface (e.g. a future "quick add several" screen).
class ManualEntrySource implements TransactionSource {
  final _staged = <RawTransaction>[];

  @override
  String get id => TransactionSourceType.manual.dbValue;

  @override
  String get displayName => 'Manual entry';

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> isAvailable() async => true;

  void stage(RawTransaction tx) => _staged.add(tx);

  @override
  Future<List<RawTransaction>> fetchTransactions({
    required PaymentCard card,
    DateTime? since,
  }) async {
    final out = _staged
        .where((t) => t.cardId == card.id && (since == null || !t.date.isBefore(since)))
        .toList();
    _staged.removeWhere(out.contains);
    return out;
  }
}
