import '../../data/models/transaction_entry.dart';

/// How a transfer with an optional fee moves money:
///
///  * the source account goes down by amount + fee,
///  * the destination receives the amount only,
///  * the fee is a separate expense in "Fees", so it counts as spending in
///    budgets and Insights (the transfer itself never does).
class TransferPlan {
  const TransferPlan({required this.amount, required this.fee});

  final int amount;
  final int fee;

  bool get hasFee => fee > 0;

  /// What leaves the source account.
  int get sourceDebit => amount + fee;

  /// What arrives at the destination (account or business capital).
  int get destinationCredit => amount;
}

class TransferFee {
  TransferFee._();

  /// Throws [ArgumentError] for a non-positive amount or a negative fee.
  static TransferPlan plan({required int amount, int fee = 0}) {
    if (amount <= 0) throw ArgumentError('Amount must be more than zero');
    if (fee < 0) throw ArgumentError('Fee can\'t be negative');
    return TransferPlan(amount: amount, fee: fee);
  }

  /// The "Fees" expense for [plan], paid from the transfer's source account.
  /// `fee_of_id` is filled in when it is saved with the transfer.
  static TransactionEntry? feeExpense(
    TransferPlan plan, {
    required int? fromAccountId,
    required int feesCategoryId,
    required DateTime date,
    required String transferLabel,
    required DateTime now,
  }) {
    if (!plan.hasFee) return null;
    return TransactionEntry(
      amount: plan.fee,
      kind: TransactionKind.expense,
      description: 'Transfer fee',
      categoryId: feesCategoryId,
      cardId: fromAccountId,
      date: date,
      notes: 'Fee for: $transferLabel',
      source: TransactionSourceType.manual,
      affectsBalance: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}
