/// Whether money went out (expense), came in (income/refund/payment),
/// moved between the user's own accounts (transfer), or went into/out of savings.
enum TransactionKind {
  expense,
  income,
  transfer,
  savings;

  static TransactionKind fromDb(String v) => switch (v) {
        'income' => TransactionKind.income,
        'transfer' => TransactionKind.transfer,
        'savings' => TransactionKind.savings,
        _ => TransactionKind.expense,
      };
}

/// Savings action: depositing into savings vs withdrawing/releasing from savings.
enum SavingsAction {
  deposit('deposit', 'Deposit'),
  withdraw('withdraw', 'Withdrawal');

  const SavingsAction(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static SavingsAction? fromDb(String? v) {
    for (final a in SavingsAction.values) {
      if (a.dbValue == v) return a;
    }
    return null;
  }
}

/// Where a transaction came from. Stored in the `source` column.
enum TransactionSourceType {
  manual('manual', 'Manual'),
  csvImport('csv_import', 'CSV import'),
  smsParsed('sms_parsed', 'SMS'),
  /// Since 1.6.0: saved by free automatic tracking (e-wallet app
  /// notifications, bank SMS alerts). Reuses the old 'bank_sync' value
  /// (allowed by the table's CHECK; there is no live bank sync).
  bankSync('bank_sync', 'Auto-tracked');

  const TransactionSourceType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static TransactionSourceType fromDb(String v) => TransactionSourceType.values
      .firstWhere((s) => s.dbValue == v, orElse: () => TransactionSourceType.manual);
}

/// How a loan was paid: from Cash or from an e-wallet. Stored in
/// `transactions.loan_paid_method`.
enum LoanPayMethod {
  cash('cash', 'Cash'),
  ewallet('ewallet', 'E-wallet');

  const LoanPayMethod(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static LoanPayMethod? fromDb(String? v) {
    for (final m in LoanPayMethod.values) {
      if (m.dbValue == v) return m;
    }
    return null;
  }
}

/// One saved transaction. Named `TransactionEntry` to avoid clashing with
/// sqflite's `Transaction` class.
class TransactionEntry {
  const TransactionEntry({
    this.id,
    required this.amount,
    required this.kind,
    required this.description,
    this.categoryId,
    this.customCategory,
    this.cardId,
    this.toCardId,
    required this.date,
    this.notes,
    this.source = TransactionSourceType.manual,
    this.externalId,
    this.dedupHash,
    this.affectsBalance = false,
    this.debtId,
    this.feeOfId,
    this.toCapital = false,
    this.fromCapital = false,
    this.loanPaidAt,
    this.loanPaidMethod,
    this.loanPaymentOfId,
    this.savingsAction,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;

  /// Always positive, in centavos. Direction is given by [kind].
  final int amount;
  final TransactionKind kind;
  final String description;
  final int? categoryId;

  /// What the user typed after picking an "Other" category, e.g. "Pet food".
  final String? customCategory;

  /// null means a cash transaction. For a transfer, the account it came from.
  final int? cardId;

  /// Transfers only: the account the money went to (null = cash).
  final int? toCardId;
  final DateTime date;
  final String? notes;
  final TransactionSourceType source;
  final String? externalId;
  final String? dedupHash;

  /// True when saving this row changed the account balances (manual entries
  /// since v5). Editing or deleting it then undoes / redoes that change.
  final bool affectsBalance;

  /// Set on the expense a new debt created, so editing or deleting the
  /// debt keeps it in sync.
  final int? debtId;

  /// Set on a "Fees" expense: the transfer whose fee it is. Deleting the
  /// transfer deletes the fee too.
  final int? feeOfId;

  /// Transfers only: the money went into business capital, not into
  /// another personal account ([toCardId] is then unused).
  final bool toCapital;

  /// Transfers only: the money came out of business capital into the
  /// personal account [toCardId] ([cardId] is then unused).
  final bool fromCapital;

  /// "Loan" transactions: when the user marked it paid (null = unpaid).
  final DateTime? loanPaidAt;

  /// "Loan" transactions: how it was paid (null for loans marked paid
  /// before the method was recorded, and for unpaid loans).
  final LoanPayMethod? loanPaidMethod;

  /// Set on the expense created when a loan was marked paid: the loan's
  /// id. It counts in the budget like any expense, and is removed when the
  /// loan is marked unpaid or deleted.
  final int? loanPaymentOfId;

  /// Savings transactions: depositing into vs withdrawing from savings.
  final SavingsAction? savingsAction;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCash => cardId == null;
  bool get isExpense => kind == TransactionKind.expense;
  bool get isIncome => kind == TransactionKind.income;
  bool get isTransfer => kind == TransactionKind.transfer;
  bool get isSavings => kind == TransactionKind.savings;
  bool get isSavingsDeposit => isSavings && (savingsAction == SavingsAction.deposit || savingsAction == null);
  bool get isSavingsWithdrawal => isSavings && savingsAction == SavingsAction.withdraw;
  bool get isCapitalTransfer => isTransfer && (toCapital || fromCapital);
  bool get isFee => feeOfId != null;
  bool get isLoanPaid => loanPaidAt != null;
  bool get isLoanPayment => loanPaymentOfId != null;

  /// A loan you gave (an expense in "Loan") that was paid back in the same
  /// month you lent it. It cancels out: it isn't counted as spending in
  /// that month's budget. Paid back in a later month, it stays counted in
  /// the month it was lent.
  bool get isLoanCancelledByRepayment =>
      isExpense && loanPaidAt != null && loanPaidAt!.year == date.year && loanPaidAt!.month == date.month;

  /// Signed amount: negative for expenses, zero for transfers (net worth
  /// doesn't change when money moves between your own accounts).
  int get signedAmount => switch (kind) {
        TransactionKind.expense => -amount,
        TransactionKind.income => amount,
        TransactionKind.transfer => 0,
        TransactionKind.savings => isSavingsWithdrawal ? amount : -amount,
      };

  TransactionEntry copyWith({
    int? id,
    int? amount,
    TransactionKind? kind,
    String? description,
    int? Function()? categoryId,
    String? Function()? customCategory,
    int? Function()? cardId,
    int? Function()? toCardId,
    DateTime? date,
    String? Function()? notes,
    TransactionSourceType? source,
    String? Function()? externalId,
    String? Function()? dedupHash,
    bool? affectsBalance,
    int? Function()? debtId,
    int? Function()? feeOfId,
    bool? toCapital,
    bool? fromCapital,
    DateTime? Function()? loanPaidAt,
    LoanPayMethod? Function()? loanPaidMethod,
    int? Function()? loanPaymentOfId,
    SavingsAction? Function()? savingsAction,
    DateTime? updatedAt,
  }) =>
      TransactionEntry(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        kind: kind ?? this.kind,
        description: description ?? this.description,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        customCategory: customCategory != null ? customCategory() : this.customCategory,
        cardId: cardId != null ? cardId() : this.cardId,
        toCardId: toCardId != null ? toCardId() : this.toCardId,
        date: date ?? this.date,
        notes: notes != null ? notes() : this.notes,
        source: source ?? this.source,
        externalId: externalId != null ? externalId() : this.externalId,
        dedupHash: dedupHash != null ? dedupHash() : this.dedupHash,
        affectsBalance: affectsBalance ?? this.affectsBalance,
        debtId: debtId != null ? debtId() : this.debtId,
        feeOfId: feeOfId != null ? feeOfId() : this.feeOfId,
        toCapital: toCapital ?? this.toCapital,
        fromCapital: fromCapital ?? this.fromCapital,
        loanPaidAt: loanPaidAt != null ? loanPaidAt() : this.loanPaidAt,
        loanPaidMethod: loanPaidMethod != null ? loanPaidMethod() : this.loanPaidMethod,
        loanPaymentOfId: loanPaymentOfId != null ? loanPaymentOfId() : this.loanPaymentOfId,
        savingsAction: savingsAction != null ? savingsAction() : this.savingsAction,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'kind': kind.name,
        'description': description,
        'category_id': categoryId,
        'custom_category': customCategory,
        'card_id': cardId,
        'to_card_id': toCardId,
        'date': date.millisecondsSinceEpoch,
        'notes': notes,
        'source': source.dbValue,
        'external_id': externalId,
        'dedup_hash': dedupHash,
        'affects_balance': affectsBalance ? 1 : 0,
        'debt_id': debtId,
        'fee_of_id': feeOfId,
        'to_capital': toCapital ? 1 : 0,
        'from_capital': fromCapital ? 1 : 0,
        'loan_paid_at': loanPaidAt?.millisecondsSinceEpoch,
        'loan_paid_method': loanPaidMethod?.dbValue,
        'loan_payment_of_id': loanPaymentOfId,
        'savings_action': savingsAction?.dbValue,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory TransactionEntry.fromMap(Map<String, Object?> m) => TransactionEntry(
        id: m['id'] as int,
        amount: m['amount'] as int,
        kind: TransactionKind.fromDb(m['kind'] as String),
        description: m['description'] as String,
        categoryId: m['category_id'] as int?,
        customCategory: m['custom_category'] as String?,
        cardId: m['card_id'] as int?,
        toCardId: m['to_card_id'] as int?,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        notes: m['notes'] as String?,
        source: TransactionSourceType.fromDb(m['source'] as String),
        externalId: m['external_id'] as String?,
        dedupHash: m['dedup_hash'] as String?,
        affectsBalance: (m['affects_balance'] as int? ?? 0) == 1,
        debtId: m['debt_id'] as int?,
        feeOfId: m['fee_of_id'] as int?,
        toCapital: (m['to_capital'] as int? ?? 0) == 1,
        fromCapital: (m['from_capital'] as int? ?? 0) == 1,
        loanPaidAt: m['loan_paid_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['loan_paid_at'] as int),
        loanPaidMethod: LoanPayMethod.fromDb(m['loan_paid_method'] as String?),
        loanPaymentOfId: m['loan_payment_of_id'] as int?,
        savingsAction: SavingsAction.fromDb(m['savings_action'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}

/// Filters for the transaction list.
class TransactionFilter {
  const TransactionFilter({
    this.cardId,
    this.cashOnly = false,
    this.categoryId,
    this.from,
    this.to,
    this.search,
    this.kind,
  });

  /// Only transactions on this card (including transfers into it).
  final int? cardId;

  /// Only cash transactions (ignored when [cardId] is set).
  final bool cashOnly;
  final int? categoryId;

  /// Inclusive start.
  final DateTime? from;

  /// Exclusive end.
  final DateTime? to;
  final String? search;
  final TransactionKind? kind;

  bool get isEmpty =>
      cardId == null &&
      !cashOnly &&
      categoryId == null &&
      from == null &&
      to == null &&
      (search == null || search!.isEmpty) &&
      kind == null;

  TransactionFilter copyWith({
    int? Function()? cardId,
    bool? cashOnly,
    int? Function()? categoryId,
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? Function()? search,
    TransactionKind? Function()? kind,
  }) =>
      TransactionFilter(
        cardId: cardId != null ? cardId() : this.cardId,
        cashOnly: cashOnly ?? this.cashOnly,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        search: search != null ? search() : this.search,
        kind: kind != null ? kind() : this.kind,
      );
}
