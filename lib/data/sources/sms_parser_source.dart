import '../../domain/sms/sms_parser.dart';
import '../models/payment_card.dart';
import '../models/raw_transaction.dart';
import '../models/sms_pattern.dart';
import '../models/transaction_entry.dart';
import 'sms_inbox.dart';
import 'transaction_source.dart';

/// Reads bank/card SMS alerts on the device (Android only, opt-in).
///
/// Messages are read and parsed locally and are never uploaded. The user
/// reviews every parsed item before anything is saved.
class SmsParserSource implements TransactionSource {
  SmsParserSource({
    required this.inbox,
    required this.patterns,
    this.includeWithoutCardNumber = false,
    this.lookback = const Duration(days: 60),
  });

  final SmsInbox inbox;
  final List<SmsPattern> patterns;

  /// Also return alerts that don't mention a card number (e.g. e-wallets).
  final bool includeWithoutCardNumber;
  final Duration lookback;

  @override
  String get id => TransactionSourceType.smsParsed.dbValue;

  @override
  String get displayName => 'SMS alerts';

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> isAvailable() async => inbox.isSupported;

  @override
  Future<List<RawTransaction>> fetchTransactions({
    required PaymentCard card,
    DateTime? since,
  }) async {
    if (!inbox.isSupported) {
      throw const SourceUnavailableException('Reading SMS is only possible on Android.');
    }
    if (!await inbox.hasPermission()) {
      throw const SourceUnavailableException('SMS permission has not been granted.');
    }
    final from = since ?? DateTime.now().subtract(lookback);
    final messages = await inbox.read(since: from);
    final parsed = SmsParser(patterns).parseAll(messages);

    return [
      for (final p in parsed)
        if (p.last4 == card.last4 || (p.last4 == null && includeWithoutCardNumber))
          RawTransaction(
            date: p.message.date,
            description: p.merchant,
            amount: p.amount,
            kind: p.kind,
            source: TransactionSourceType.smsParsed,
            cardId: card.id,
            externalId: p.reference != null ? 'ref:${p.reference}' : 'sms:${p.message.id}',
            originalText: p.message.body,
          ),
    ];
  }
}
