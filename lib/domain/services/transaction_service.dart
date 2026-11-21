import '../../data/models/raw_transaction.dart';
import '../../data/models/transaction_entry.dart';
import '../../data/repositories/account_ledger.dart';
import '../../data/models/business.dart';
import '../../data/repositories/business_repositories.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../import/transaction_import_service.dart';
import '../business/capital_math.dart';
import '../transfer/transfer_fee.dart';
import 'budget_alert_service.dart';

/// Create / edit / delete for the UI. Creating goes through the import
/// pipeline so manual entries are categorized the same way as imports.
class TransactionService {
  TransactionService({
    required TransactionRepository repository,
    required this._cards,
    required this._importer,
    required this._alerts,
    this._categories,
    DateTime Function()? clock,
  })  : _repo = repository,
        _clock = clock ?? DateTime.now;

  final TransactionRepository _repo;
  final CardRepository _cards;
  final TransactionImportService _importer;
  final BudgetAlertService _alerts;

  /// For the "Fees" category of transfer fees.
  final CategoryRepository? _categories;
  final DateTime Function() _clock;

  Future<int> create(RawTransaction raw) => _importer.saveManual(raw);

  Future<void> update(TransactionEntry tx) async {
    if (tx.id == null) throw ArgumentError('Transaction has no id');
    if (tx.amount <= 0) throw ArgumentError('Amount must be greater than zero');
    if (tx.isTransfer && tx.cardId == tx.toCardId) {
      throw ArgumentError('A transfer needs two different accounts');
    }
    final description = tx.description.trim().isEmpty ? 'Unknown' : tx.description.trim();
    final hash = TransactionImportService.hashOf(RawTransaction(
      date: tx.date,
      description: description,
      amount: tx.amount,
      kind: tx.kind,
      source: tx.source,
      cardId: tx.cardId,
    ));
    await _repo.update(tx.copyWith(
      description: description,
      dedupHash: () => hash,
      updatedAt: DateTime.now(),
    ));
    await _alerts.checkMonth(tx.date);
  }

  /// A transfer between accounts, or into business capital, with an
  /// optional fee ([TransferFee]): the source goes down by amount + fee,
  /// the destination gets the amount, and the fee is saved as a "Fees"
  /// expense. Everything is one SQLite transaction. Returns the transfer id.
  Future<int> createTransfer({
    required int amount,
    int fee = 0,
    required int? fromAccountId,
    int? toAccountId,
    bool toCapital = false,
    required DateTime date,
    String? description,
    String? notes,
    String? opKey,
  }) async {
    final plan = TransferFee.plan(amount: amount, fee: fee);
    if (!toCapital && fromAccountId == toAccountId) {
      throw ArgumentError('A transfer needs two different accounts');
    }
    final now = _clock();
    final label = (description == null || description.trim().isEmpty)
        ? (toCapital ? 'Business capital' : 'Transfer')
        : description.trim();
    final transfer = TransactionEntry(
      amount: plan.amount,
      kind: TransactionKind.transfer,
      description: label,
      cardId: fromAccountId,
      toCardId: toCapital ? null : toAccountId,
      toCapital: toCapital,
      date: date,
      notes: notes,
      source: TransactionSourceType.manual,
      affectsBalance: true,
      createdAt: now,
      updatedAt: now,
    );
    TransactionEntry? feeRow;
    if (plan.hasFee) {
      final categories = _categories;
      if (categories == null) throw StateError('Fees category unavailable');
      feeRow = TransferFee.feeExpense(
        plan,
        fromAccountId: fromAccountId,
        feesCategoryId: await categories.feesCategoryId(),
        date: date,
        transferLabel: label,
        now: now,
      );
    }
    final id = await _repo.insertTransfer(
      transfer,
      fee: feeRow,
      opKey: opKey,
      afterInsert: toCapital
          ? (txn, transferId) => CapitalRepository.insertInTxn(
                txn,
                CapitalEntry(
                  amount: plan.destinationCredit,
                  kind: CapitalKind.deposit,
                  note: notes,
                  date: date,
                  transactionId: transferId,
                  createdAt: now,
                ),
              )
          : null,
    );
    if (plan.hasFee) await _alerts.checkMonth(date);
    return id;
  }

  /// Takes money out of business capital into a personal account (null =
  /// Cash), as a transfer: the account gets [amount]; capital goes down by
  /// amount + fee (a "withdrawal" and a "fee" ledger row). The limit is
  /// checked again inside the SQLite transaction, so two quick withdrawals
  /// can't take more than the balance. Each [opKey] runs once.
  Future<int> withdrawFromCapital({
    required int amount,
    int fee = 0,
    required int? toAccountId,
    required DateTime date,
    String? notes,
    String? opKey,
  }) async {
    if (amount <= 0) throw ArgumentError('Amount must be more than zero');
    if (fee < 0) throw ArgumentError('Fee can\'t be negative');
    final now = _clock();
    final transfer = TransactionEntry(
      amount: amount,
      kind: TransactionKind.transfer,
      description: 'From business capital',
      toCardId: toAccountId,
      fromCapital: true,
      date: date,
      notes: notes,
      source: TransactionSourceType.manual,
      affectsBalance: true,
      createdAt: now,
      updatedAt: now,
    );
    return _repo.insertTransfer(
      transfer,
      opKey: opKey,
      afterInsert: (txn, transferId) async {
        final balance = await CapitalRepository.balanceIn(txn);
        final plan = CapitalMath.planWithdraw(balance: balance, amount: amount, fee: fee);
        for (final e in CapitalMath.withdrawEntries(plan, date: date, now: now, transactionId: transferId, note: notes)) {
          await CapitalRepository.insertInTxn(txn, e);
        }
      },
    );
  }

  /// The fee saved with a transfer, if any.
  Future<int> feeOf(int transferId) async =>
      (await _repo.feesOf(transferId)).fold<int>(0, (a, t) => a + t.amount);

  /// Transactions in the "Loan" category, for the Loans section.
  Future<List<TransactionEntry>> loans() => _repo.loans();

  /// Marks a loan row paid (or unpaid with null). Changes only that row:
  /// no new expense, no balance change.
  Future<void> setLoanPaid(int id, DateTime? paidAt) => _repo.setLoanPaid(id, paidAt);

  /// Undoes the row's balance change (if any) and deletes it, atomically.
  Future<void> delete(int id) => _repo.delete(id);

  /// How much is in the account an expense or transfer would be paid from,
  /// before this transaction. When [editing] already took money out of that
  /// same account, that amount is counted as available again.
  ///
  /// Returns null when the balance isn't affected (income, or an edit of an
  /// imported / pre-balance row), so there is nothing to check.
  Future<int?> availableBefore({
    required TransactionKind kind,
    required int? accountId,
    TransactionEntry? editing,
  }) async {
    if (kind == TransactionKind.income) return null;
    if (editing != null && !editing.affectsBalance) return null;
    var available = await _cards.balanceOf(accountId);
    if (editing != null) {
      for (final (account, delta) in AccountLedger.effects(editing)) {
        if (account == accountId) available -= delta;
      }
    }
    return available;
  }

  Future<int?> suggestCategory(String description) => _importer.suggestCategory(description);
}
