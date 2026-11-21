class Debt {
  const Debt({
    this.id,
    required this.creditor,
    required this.totalAmount,
    this.initialPaid = 0,
    this.dueDate,
    this.interestRateBp,
    this.notes,
    this.isPaid = false,
    required this.createdAt,
    this.paidAt,
  });

  final int? id;
  final String creditor;

  /// Centavos.
  final int totalAmount;

  /// Amount already paid when the debt was added (centavos).
  final int initialPaid;
  final DateTime? dueDate;

  /// Interest rate in basis points: 350 = 3.50%.
  final int? interestRateBp;
  final String? notes;
  final bool isPaid;
  final DateTime createdAt;
  final DateTime? paidAt;

  Debt copyWith({
    String? creditor,
    int? totalAmount,
    int? initialPaid,
    DateTime? Function()? dueDate,
    int? Function()? interestRateBp,
    String? Function()? notes,
    bool? isPaid,
    DateTime? Function()? paidAt,
  }) =>
      Debt(
        id: id,
        creditor: creditor ?? this.creditor,
        totalAmount: totalAmount ?? this.totalAmount,
        initialPaid: initialPaid ?? this.initialPaid,
        dueDate: dueDate != null ? dueDate() : this.dueDate,
        interestRateBp: interestRateBp != null ? interestRateBp() : this.interestRateBp,
        notes: notes != null ? notes() : this.notes,
        isPaid: isPaid ?? this.isPaid,
        createdAt: createdAt,
        paidAt: paidAt != null ? paidAt() : this.paidAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'creditor': creditor,
        'total_amount': totalAmount,
        'initial_paid': initialPaid,
        'due_date': dueDate?.millisecondsSinceEpoch,
        'interest_rate_bp': interestRateBp,
        'notes': notes,
        'is_paid': isPaid ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'paid_at': paidAt?.millisecondsSinceEpoch,
      };

  factory Debt.fromMap(Map<String, Object?> m) => Debt(
        id: m['id'] as int,
        creditor: m['creditor'] as String,
        totalAmount: m['total_amount'] as int,
        initialPaid: m['initial_paid'] as int? ?? 0,
        dueDate: m['due_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
        interestRateBp: m['interest_rate_bp'] as int?,
        notes: m['notes'] as String?,
        isPaid: (m['is_paid'] as int? ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        paidAt: m['paid_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['paid_at'] as int),
      );
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
  const DebtStatus({required this.debt, required this.paymentsTotal});

  final Debt debt;
  final int paymentsTotal;

  int get paid => debt.initialPaid + paymentsTotal;
  int get remaining {
    final r = debt.totalAmount - paid;
    return r < 0 ? 0 : r;
  }

  double get progress =>
      debt.totalAmount == 0 ? 1 : (paid / debt.totalAmount).clamp(0.0, 1.0);

  bool get isSettled => debt.isPaid || remaining == 0;

  bool isOverdue(DateTime now) =>
      !isSettled && debt.dueDate != null && debt.dueDate!.isBefore(now);
}
