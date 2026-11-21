import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/data/repositories/account_ledger.dart';
import 'package:budgeting_app/domain/budget/budget_calculator.dart';
import 'package:budgeting_app/domain/transfer/transfer_fee.dart';
import 'package:flutter_test/flutter_test.dart';

const gcash = 1;
const bpi = 2;
const feesCategory = 77;

void main() {
  final now = DateTime(2026, 11, 21, 10);

  TransactionEntry transfer(int amount, {bool toCapital = false}) => TransactionEntry(
        amount: amount,
        kind: TransactionKind.transfer,
        description: 'Transfer',
        cardId: gcash,
        toCardId: toCapital ? null : bpi,
        toCapital: toCapital,
        date: now,
        affectsBalance: true,
        createdAt: now,
        updatedAt: now,
      );

  /// Net balance change per account (null = Cash) from all [rows].
  Map<int?, int> net(List<TransactionEntry> rows) {
    final out = <int?, int>{};
    for (final r in rows) {
      for (final (account, delta) in AccountLedger.effects(r)) {
        out[account] = (out[account] ?? 0) + delta;
      }
    }
    return out;
  }

  test('plan: source pays amount + fee, destination gets the amount', () {
    final p = TransferFee.plan(amount: 100000, fee: 1500);
    expect(p.sourceDebit, 101500);
    expect(p.destinationCredit, 100000);
    expect(p.hasFee, isTrue);
  });

  test('no fee: nothing extra and no fee expense', () {
    final p = TransferFee.plan(amount: 100000);
    expect(p.sourceDebit, 100000);
    expect(
      TransferFee.feeExpense(p, fromAccountId: gcash, feesCategoryId: feesCategory, date: now, transferLabel: 'x', now: now),
      isNull,
    );
  });

  test('invalid amounts are rejected', () {
    expect(() => TransferFee.plan(amount: 0), throwsArgumentError);
    expect(() => TransferFee.plan(amount: 100, fee: -1), throwsArgumentError);
  });

  test('transfer + fee expense move balances by amount + fee and amount', () {
    final p = TransferFee.plan(amount: 100000, fee: 1500);
    final fee = TransferFee.feeExpense(p, fromAccountId: gcash, feesCategoryId: feesCategory, date: now, transferLabel: 'To BPI', now: now)!;
    expect(fee.kind, TransactionKind.expense);
    expect(fee.categoryId, feesCategory);
    expect(fee.cardId, gcash);
    expect(fee.amount, 1500);
    expect(fee.affectsBalance, isTrue);

    final balances = net([transfer(p.amount), fee]);
    expect(balances[gcash], -101500);
    expect(balances[bpi], 100000);
  });

  test('only the fee counts as spending (totals stay accurate)', () {
    final p = TransferFee.plan(amount: 100000, fee: 1500);
    final fee = TransferFee.feeExpense(p, fromAccountId: gcash, feesCategoryId: feesCategory, date: now, transferLabel: 'x', now: now)!;
    final rows = [transfer(p.amount), fee];
    expect(BudgetCalculator.spent(rows), 1500);
    expect(BudgetCalculator.spent(rows, categoryId: feesCategory), 1500);
  });

  test('into business capital: the personal account goes down, no other personal account goes up', () {
    final p = TransferFee.plan(amount: 50000, fee: 1000);
    final fee = TransferFee.feeExpense(p, fromAccountId: gcash, feesCategoryId: feesCategory, date: now, transferLabel: 'Capital', now: now)!;
    final balances = net([transfer(p.amount, toCapital: true), fee]);
    expect(balances[gcash], -51000);
    // A capital transfer's null destination must not be read as Cash.
    expect(balances.containsKey(null), isFalse);
    expect(balances.containsKey(bpi), isFalse);
  });
}
