import '../../data/models/business.dart';

class CapitalLimitException implements Exception {
  const CapitalLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A withdrawal: capital goes down by amount + fee, the personal account
/// gets the amount, and the fee is its own capital ledger row.
class WithdrawPlan {
  const WithdrawPlan({required this.amount, required this.fee});
  final int amount;
  final int fee;
  int get capitalDebit => amount + fee;
  int get personalCredit => amount;
  bool get hasFee => fee > 0;
}

/// Pure capital ledger logic (unit tested).
class CapitalMath {
  CapitalMath._();

  /// The balance is always the sum of the ledger.
  static int balance(Iterable<CapitalEntry> entries) => entries.fold(0, (a, e) => a + e.amount);

  /// Null when the withdrawal is allowed, else the reason.
  static String? withdrawError({required int balance, required int amount, int fee = 0}) {
    if (amount <= 0) return 'Amount must be more than zero';
    if (fee < 0) return 'Fee can\'t be negative';
    if (balance <= 0) return 'There is no capital to withdraw';
    if (amount + fee > balance) return 'More than the capital balance';
    return null;
  }

  /// Throws [CapitalLimitException] when amount + fee is more than [balance].
  static WithdrawPlan planWithdraw({required int balance, required int amount, int fee = 0}) {
    final error = withdrawError(balance: balance, amount: amount, fee: fee);
    if (error != null) throw CapitalLimitException(error);
    return WithdrawPlan(amount: amount, fee: fee);
  }

  /// Ledger rows for a withdrawal (fee as its own row).
  static List<CapitalEntry> withdrawEntries(
    WithdrawPlan plan, {
    required DateTime date,
    required DateTime now,
    int? transactionId,
    String? note,
  }) =>
      [
        CapitalEntry(amount: -plan.amount, kind: CapitalKind.withdrawal, note: note, date: date, transactionId: transactionId, createdAt: now),
        if (plan.hasFee)
          CapitalEntry(amount: -plan.fee, kind: CapitalKind.fee, note: 'Withdrawal fee', date: date, transactionId: transactionId, createdAt: now),
      ];
}
