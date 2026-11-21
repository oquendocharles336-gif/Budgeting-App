/// A credit/debit/prepaid card the user tracks.
///
/// Named `PaymentCard` (not `Card`) so it doesn't clash with Flutter's
/// Material `Card` widget.
enum CardType {
  credit('Credit'),
  debit('Debit'),
  prepaid('Prepaid'),
  ewallet('E-wallet');

  const CardType(this.label);
  final String label;

  static CardType fromDb(String value) =>
      CardType.values.firstWhere((t) => t.name == value, orElse: () => CardType.credit);
}

class PaymentCard {
  const PaymentCard({
    this.id,
    required this.nickname,
    required this.last4,
    required this.type,
    required this.color,
    this.archived = false,
    required this.createdAt,
  });

  final int? id;
  final String nickname;
  final String last4;
  final CardType type;

  /// ARGB color value, e.g. 0xFF3F51B5.
  final int color;
  final bool archived;
  final DateTime createdAt;

  String get label => '$nickname •••• $last4';

  PaymentCard copyWith({
    int? id,
    String? nickname,
    String? last4,
    CardType? type,
    int? color,
    bool? archived,
  }) =>
      PaymentCard(
        id: id ?? this.id,
        nickname: nickname ?? this.nickname,
        last4: last4 ?? this.last4,
        type: type ?? this.type,
        color: color ?? this.color,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'nickname': nickname,
        'last4': last4,
        'card_type': type.name,
        'color': color,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory PaymentCard.fromMap(Map<String, Object?> m) => PaymentCard(
        id: m['id'] as int,
        nickname: m['nickname'] as String,
        last4: m['last4'] as String,
        type: CardType.fromDb(m['card_type'] as String),
        color: m['color'] as int,
        archived: (m['archived'] as int? ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
