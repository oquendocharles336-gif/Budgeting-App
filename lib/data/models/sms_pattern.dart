import 'transaction_entry.dart';

/// A user-editable rule for reading one bank's SMS alerts.
///
/// [bodyPattern] is a regular expression with named groups:
///   `(?<amount>...)`   required, e.g. 1,234.56
///   `(?<merchant>...)` optional
///   `(?<last4>...)`    optional, last 4 digits of the card
class SmsPattern {
  const SmsPattern({
    this.id,
    required this.bankName,
    this.senderPattern = '',
    required this.bodyPattern,
    this.kind = TransactionKind.expense,
    this.enabled = true,
  });

  final int? id;
  final String bankName;

  /// Case-insensitive regex matched against the SMS sender (address).
  /// Empty = any sender.
  final String senderPattern;
  final String bodyPattern;
  final TransactionKind kind;
  final bool enabled;

  SmsPattern copyWith({
    String? bankName,
    String? senderPattern,
    String? bodyPattern,
    TransactionKind? kind,
    bool? enabled,
  }) =>
      SmsPattern(
        id: id,
        bankName: bankName ?? this.bankName,
        senderPattern: senderPattern ?? this.senderPattern,
        bodyPattern: bodyPattern ?? this.bodyPattern,
        kind: kind ?? this.kind,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'bank_name': bankName,
        'sender_pattern': senderPattern,
        'body_pattern': bodyPattern,
        'kind': kind.name,
        'enabled': enabled ? 1 : 0,
      };

  factory SmsPattern.fromMap(Map<String, Object?> m) => SmsPattern(
        id: m['id'] as int,
        bankName: m['bank_name'] as String,
        senderPattern: m['sender_pattern'] as String? ?? '',
        bodyPattern: m['body_pattern'] as String,
        kind: TransactionKind.fromDb(m['kind'] as String? ?? 'expense'),
        enabled: (m['enabled'] as int? ?? 1) == 1,
      );
}

/// One SMS as read from the phone's inbox.
class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.address,
    required this.body,
    required this.date,
  });

  final String id;
  final String address;
  final String body;
  final DateTime date;
}
