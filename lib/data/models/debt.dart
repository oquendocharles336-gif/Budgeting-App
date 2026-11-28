import '../../domain/debt/monthly_due.dart';

/// Direction: borrowed (I owe money to someone) vs lent (someone owes money to me / loan given).
enum DebtDirection {
  borrowed('borrowed', 'Borrowed (I owe)'),
  lent('lent', 'Lent (Owed to me)');

  const DebtDirection(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DebtDirection fromDb(String? v) => v == 'lent' ? DebtDirection.lent : DebtDirection.borrowed;
}

/// What kind of debt this is. Stored in `debts.debt_type`.
enum DebtType {
  loan('Loan'),
  installment('Installment'),
  personal('Personal'),
  other('Other');

  const DebtType(this.label);
  final String label;

  static DebtType fromDb(String? v) =>
      DebtType.values.firstWhere((t) => t.name == v, orElse: () => DebtType.other);
}

/// Where the money was borrowed from or lent to. Stored in `debts.lender_type`.
enum LenderType {
  bank('Bank'),
  lendingApp('Lending app'),
  cooperative('Cooperative'),
  family('Family / friend'),
  employer('Employer'),
  creditCard('Credit card'),
  pawnshop('Pawnshop'),
  other('Other');

  const LenderType(this.label);
  final String label;

  static LenderType? fromDb(String? v) {
    for (final t in LenderType.values) {
      if (t.name == v) return t;
    }
    return null;
  }
}

/// Simple: interest is always on the amount borrowed.
/// Compound: interest is on what's still owed, so it changes as you pay.
enum InterestType {
  simple('Simple'),
  compound('Compound');

  const InterestType(this.label);
  final String label;

  static InterestType fromDb(String? v) => v == 'compound' ? InterestType.compound : InterestType.simple;
}

enum InterestPeriod {
  month('per month'),
  year('per year');

  const InterestPeriod(this.label);
  final String label;

  static InterestPeriod fromDb(String? v) => v == 'year' ? InterestPeriod.year : InterestPeriod.month;
}

class Debt {
  const Debt({
    this.id,
    required this.creditor,
    this.direction = DebtDirection.borrowed,
    this.type = DebtType.other,
    this.lenderType,
    this.lenderDetail,
    required this.totalAmount,
    this.initialPaid = 0,
    this.dueDay,
    this.dueFrom,
    this.interestRateBp,
    this.interestType = InterestType.simple,
    this.interestPeriod = InterestPeriod.month,
    this.termMonths,
    this.notes,
    this.isPaid = false,
    this.isNew = false,
    required this.createdAt,
    this.paidAt,
  });

  final int? id;

  /// True: money just received or spent, so it was also added to expenses
  /// (a linked transaction). False: an existing debt, only a reminder.
  final bool isNew;
  final DebtDirection direction;
  final String creditor;
  final DebtType type;

  /// Where it was borrowed from / lent to.
  final LenderType? lenderType;

  /// What the user typed when [lenderType] is "Other".
  final String? lenderDetail;

  /// Centavos.
  final int totalAmount;

  /// Amount already paid when the debt was added (centavos).
  final int initialPaid;

  /// Day of the month the payment is due, 1-31.
  final int? dueDay;

  /// When the monthly schedule starts counting.
  final DateTime? dueFrom;

  /// Interest rate in basis points.
  final int? interestRateBp;
  final InterestType interestType;
  final InterestPeriod interestPeriod;

  /// Loan term: number of monthly payments.
  final int? termMonths;

  bool get isBorrowed => direction == DebtDirection.borrowed;
  bool get isLent => direction == DebtDirection.lent;

  /// The monthly schedule, or null without a [dueDay].
  MonthlyDue? get schedule => dueDay == null ? null : MonthlyDue(day: dueDay!, startedAt: dueFrom ?? createdAt);

  /// "Bank", or the typed text for "Other".
  String? get lenderLabel {
    final t = lenderType;
    if (t == null) return null;
    if (t == LenderType.other && (lenderDetail?.trim().isNotEmpty ?? false)) return lenderDetail!.trim();
    return t.label;
  }
  final String? notes;
  final bool isPaid;
  final DateTime createdAt;
  final DateTime? paidAt;

  Debt copyWith({
    String? creditor,
    DebtDirection? direction,
    DebtType? type,
    LenderType? Function()? lenderType,
    String? Function()? lenderDetail,
    InterestType? interestType,
    InterestPeriod? interestPeriod,
    int? Function()? termMonths,
    int? totalAmount,
    int? initialPaid,
    int? Function()? dueDay,
    DateTime? Function()? dueFrom,
    int? Function()? interestRateBp,
    String? Function()? notes,
    bool? isPaid,
    DateTime? Function()? paidAt,
  }) =>
      Debt(
        id: id,
        creditor: creditor ?? this.creditor,
        direction: direction ?? this.direction,
        type: type ?? this.type,
        lenderType: lenderType != null ? lenderType() : this.lenderType,
        lenderDetail: lenderDetail != null ? lenderDetail() : this.lenderDetail,
        interestType: interestType ?? this.interestType,
        interestPeriod: interestPeriod ?? this.interestPeriod,
        termMonths: termMonths != null ? termMonths() : this.termMonths,
        totalAmount: totalAmount ?? this.totalAmount,
        initialPaid: initialPaid ?? this.initialPaid,
        dueDay: dueDay != null ? dueDay() : this.dueDay,
        dueFrom: dueFrom != null ? dueFrom() : this.dueFrom,
        interestRateBp: interestRateBp != null ? interestRateBp() : this.interestRateBp,
        notes: notes != null ? notes() : this.notes,
        isPaid: isPaid ?? this.isPaid,
        isNew: isNew,
        createdAt: createdAt,
        paidAt: paidAt != null ? paidAt() : this.paidAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'creditor': creditor,
        'direction': direction.dbValue,
        'debt_type': type.name,
        'lender_type': lenderType?.name,
        'lender_detail': lenderDetail,
        'interest_type': interestType.name,
        'interest_period': interestPeriod.name,
        'term_months': termMonths,
        'total_amount': totalAmount,
        'initial_paid': initialPaid,
        'due_day': dueDay,
        'due_from': dueFrom?.millisecondsSinceEpoch,
        'due_date': null,
        'interest_rate_bp': interestRateBp,
        'notes': notes,
        'is_paid': isPaid ? 1 : 0,
        'origin': isNew ? 'new' : 'existing',
        'created_at': createdAt.millisecondsSinceEpoch,
        'paid_at': paidAt?.millisecondsSinceEpoch,
      };

  factory Debt.fromMap(Map<String, Object?> m) => Debt(
        id: m['id'] as int,
        creditor: m['creditor'] as String,
        direction: DebtDirection.fromDb(m['direction'] as String?),
        type: DebtType.fromDb(m['debt_type'] as String?),
        lenderType: LenderType.fromDb(m['lender_type'] as String?),
        lenderDetail: m['lender_detail'] as String?,
        interestType: InterestType.fromDb(m['interest_type'] as String?),
        interestPeriod: InterestPeriod.fromDb(m['interest_period'] as String?),
        termMonths: m['term_months'] as int?,
        totalAmount: m['total_amount'] as int,
        initialPaid: m['initial_paid'] as int? ?? 0,
        dueDay: _dueDayOf(m),
        dueFrom: m['due_from'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['due_from'] as int),
        interestRateBp: m['interest_rate_bp'] as int?,
        notes: m['notes'] as String?,
        isPaid: (m['is_paid'] as int? ?? 0) == 1,
        isNew: m['origin'] == 'new',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        paidAt: m['paid_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['paid_at'] as int),
      );
}

/// `due_day` (v12+).
int? _dueDayOf(Map<String, Object?> m) {
  final day = m['due_day'];
  if (day is int && day >= 1 && day <= 31) return day;
  final old = m['due_date'];
  if (old is int) return DateTime.fromMillisecondsSinceEpoch(old).day;
  return null;
}

class DebtPayment {
  const DebtPayment({
    this.id,
    required this.debtId,
    required this.amount,
    required this.date,
    this.note,
  });

  final int? id;
  final int debtId;
  final int amount;
  final DateTime date;
  final String? note;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'debt_id': debtId,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'note': note,
      };

  factory DebtPayment.fromMap(Map<String, Object?> m) => DebtPayment(
        id: m['id'] as int,
        debtId: m['debt_id'] as int,
        amount: m['amount'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        note: m['note'] as String?,
      );
}

/// A debt plus the totals computed from its payments.
class DebtStatus {
  const DebtStatus({required this.debt, required this.paymentsTotal, this.paymentsCount = 0});

  final Debt debt;
  final int paymentsTotal;

  /// How many payments were recorded (one per month is expected).
  final int paymentsCount;

  int get paid => debt.initialPaid + paymentsTotal;
  int get remaining {
    final r = debt.totalAmount - paid;
    return r < 0 ? 0 : r;
  }

  double get progress =>
      debt.totalAmount == 0 ? 1 : (paid / debt.totalAmount).clamp(0.0, 1.0);

  bool get isSettled => debt.isPaid || remaining == 0;

  /// The due date the next reminder is for (today or later), or null when
  /// settled or there is no due day.
  DateTime? nextDue(DateTime now) => isSettled ? null : debt.schedule?.nextDue(now, paymentsCount);

  /// The oldest monthly due date that passed without a payment, or null.
  DateTime? overdueSince(DateTime now) => isSettled ? null : debt.schedule?.overdueSince(now, paymentsCount);

  /// A monthly payment day passed and no payment was recorded for it.
  bool isOverdue(DateTime now) => overdueSince(now) != null;
}
