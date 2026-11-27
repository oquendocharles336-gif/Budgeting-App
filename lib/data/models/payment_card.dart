import '../../core/ewallet_mask.dart';
import '../../core/wallet_apps.dart';

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
    this.mobileNumber,
    this.balance = 0,
    this.archived = false,
    this.notifyApp,
    this.autoTrackSince,
    required this.createdAt,
  });

  final int? id;
  final String nickname;
  final String last4;
  final CardType type;

  /// ARGB color value, e.g. 0xFF3F51B5.
  final int color;

  /// E-wallets only: the full mobile number (e.g. "09123456768"). Stored
  /// unmasked; use [maskedNumber] / [label] to show it.
  final String? mobileNumber;

  /// Money in the account right now, in centavos. For a credit card this is
  /// the credit still available. Can go below zero if the user confirms an
  /// expense larger than the balance.
  final int balance;
  final bool archived;
  final DateTime createdAt;

  /// Free automatic tracking: the app whose payment notifications are
  /// read for this account ([WalletApp.id], e.g. 'maya'). Null = none.
  final String? notifyApp;

  /// When automatic tracking was turned on. Only payments after this are
  /// recorded (and taken from [balance]), so money already in the balance
  /// typed by the user isn't charged twice. Null = tracking off.
  final DateTime? autoTrackSince;

  /// Automatic tracking is on (app notifications and, for cards with a
  /// last-4, bank SMS alerts).
  bool get tracksAutomatically => autoTrackSince != null && !archived;

  WalletApp? get walletApp => WalletApp.fromId(notifyApp);

  bool get isCredit => type == CardType.credit;

  /// Credit isn't the user's own money, so it is left out of "available balance".
  bool get countsTowardAvailable => !isCredit && !archived;

  /// "Balance" or "Available credit".
  String get balanceLabel => isCredit ? 'Available credit' : 'Balance';

  bool get hasMobileNumber => type == CardType.ewallet && (mobileNumber?.trim().isNotEmpty ?? false);

  /// The number as it should be displayed: a masked mobile number for
  /// e-wallets ("09******768"), otherwise "•••• 1234".
  String get maskedNumber => hasMobileNumber ? maskEWalletNumber(mobileNumber!) : '•••• $last4';

  String get label => '$nickname $maskedNumber';

  /// Compact form for chips and list subtitles.
  String get shortLabel => hasMobileNumber ? '$nickname ${maskEWalletNumber(mobileNumber!)}' : '$nickname ••$last4';

  PaymentCard copyWith({
    int? id,
    String? nickname,
    String? last4,
    CardType? type,
    int? color,
    String? Function()? mobileNumber,
    int? balance,
    bool? archived,
    String? Function()? notifyApp,
    DateTime? Function()? autoTrackSince,
  }) =>
      PaymentCard(
        id: id ?? this.id,
        nickname: nickname ?? this.nickname,
        last4: last4 ?? this.last4,
        type: type ?? this.type,
        color: color ?? this.color,
        mobileNumber: mobileNumber != null ? mobileNumber() : this.mobileNumber,
        balance: balance ?? this.balance,
        archived: archived ?? this.archived,
        notifyApp: notifyApp != null ? notifyApp() : this.notifyApp,
        autoTrackSince: autoTrackSince != null ? autoTrackSince() : this.autoTrackSince,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'nickname': nickname,
        'last4': last4,
        'card_type': type.name,
        'color': color,
        'mobile_number': mobileNumber,
        'balance': balance,
        'archived': archived ? 1 : 0,
        'notify_app': notifyApp,
        'auto_track_since': autoTrackSince?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory PaymentCard.fromMap(Map<String, Object?> m) => PaymentCard(
        id: m['id'] as int,
        nickname: m['nickname'] as String,
        last4: m['last4'] as String,
        type: CardType.fromDb(m['card_type'] as String),
        color: m['color'] as int,
        mobileNumber: m['mobile_number'] as String?,
        balance: m['balance'] as int? ?? 0,
        archived: (m['archived'] as int? ?? 0) == 1,
        notifyApp: m['notify_app'] as String?,
        autoTrackSince: m['auto_track_since'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['auto_track_since'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
