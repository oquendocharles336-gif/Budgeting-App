import '../../data/models/raw_transaction.dart';
import '../../data/models/transaction_entry.dart';
import '../../data/repositories/account_ledger.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../import/transaction_import_service.dart';
import 'budget_alert_service.dart';

/// Create / edit / delete for the UI. Creating goes through the import
/// pipeline so manual entries are categorized the same way as imports.
class TransactionService {
  TransactionService({
    required TransactionRepository repository,
    required this._cards,
    required this._importer,
    required this._alerts,
  }) : _repo = repository;

  final TransactionRepository _repo;
  final CardRepository _cards;
  final TransactionImportService _importer;
  final BudgetAlertService _alerts;

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
