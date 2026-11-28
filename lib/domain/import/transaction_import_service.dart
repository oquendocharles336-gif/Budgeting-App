import '../../data/db/default_data.dart';
import '../../data/models/payment_card.dart';
import '../../data/models/raw_transaction.dart';
import '../../data/models/transaction_entry.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/sources/transaction_source.dart';
import '../services/budget_alert_service.dart';
import 'auto_categorizer.dart';
import 'deduplicator.dart';

/// One row in an import preview.
class ImportCandidate {
  ImportCandidate({
    required this.raw,
    required this.categoryId,
    required this.hash,
    this.duplicate,
    bool? selected,
  }) : selected = selected ?? duplicate == null;

  final RawTransaction raw;
  int? categoryId;
  final String hash;
  final DuplicateReason? duplicate;

  /// Whether the user wants to save it. Duplicates start unticked.
  bool selected;

  bool get isDuplicate => duplicate != null;
}

class ImportResult {
  const ImportResult({required this.inserted, required this.skipped});
  final int inserted;
  final int skipped;
}

/// The single pipeline every source goes through:
///   fetch -> normalize -> auto-categorize -> de-duplicate -> (review) -> save
class TransactionImportService {
  // `this._x` named parameters are called as `x:` (Dart private named parameters).
  TransactionImportService({
    required this._transactions,
    required this._rules,
    this._alerts,
    this._categories,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository _transactions;
  final RuleRepository _rules;
  final BudgetAlertService? _alerts;

  /// Used to file income under "Other income" instead of expense rules.
  final CategoryRepository? _categories;
  final DateTime Function() _clock;

  static const maxDescriptionLength = 200;

  /// Fetches from [source] and returns candidates for the review screen.
  Future<List<ImportCandidate>> preview(
    TransactionSource source, {
    required PaymentCard card,
    DateTime? since,
  }) async {
    if (!await source.isAvailable()) {
      throw SourceUnavailableException('${source.displayName} is not available on this device.');
    }
    final raws = await source.fetchTransactions(card: card, since: since);
    return prepare(raws);
  }

  /// Normalizes, categorizes and flags duplicates. Saves nothing.
  Future<List<ImportCandidate>> prepare(List<RawTransaction> raws) async {
    final categorizer = await _categorizer();
    final otherIncome = await _categories?.otherIncomeId();
    final items = raws.map(normalize).where((r) => r.amount > 0).toList();
    final keys = [
      for (final r in items) DedupKey(hash: hashOf(r), cardId: r.cardId, externalId: r.externalId),
    ];
    final existingExternal = await _transactions.existingExternalIds(items.map((r) => r.cardId));
    final counts = await _transactions.hashCounts(keys.map((k) => k.hash));
    final duplicates = Deduplicator.findDuplicates(
      keys,
      existingExternalIds: existingExternal,
      existingHashCounts: counts,
    );
    return [
      for (var i = 0; i < items.length; i++)
        ImportCandidate(
          raw: items[i],
          categoryId: items[i].categoryId ??
              (items[i].kind == TransactionKind.income && otherIncome != null
                  ? otherIncome
                  : categorizer.categorize(items[i].description)),
          hash: keys[i].hash,
          duplicate: duplicates[i],
        ),
    ];
  }

  /// Saves the selected candidates.
  ///
  /// A candidate the user ticked even though it matched by details is saved
  /// (they know best). One whose external ID already exists is always
  /// skipped, because the database can only hold it once.
  ///
  /// [moveBalances]: automatic tracking (app notifications / SMS after the
  /// account was connected) takes each expense from the account balance,
  /// like a typed entry. Reviewed imports don't (their money is already in
  /// the balance the user typed).
  Future<ImportResult> commit(List<ImportCandidate> candidates, {bool moveBalances = false}) async {
    final chosen = candidates.where((c) => c.selected).toList();
    final seen = await _transactions.existingExternalIds(chosen.map((c) => c.raw.cardId));
    var skipped = candidates.length - chosen.length;
    final now = _clock();
    final rows = <TransactionEntry>[];
    for (final c in chosen) {
      final ext = c.raw.externalId;
      if (ext != null) {
        final scoped = DedupKey.scopeExternalId(c.raw.cardId, ext);
        if (seen.contains(scoped)) {
          skipped++;
          continue;
        }
        seen.add(scoped);
      }
      rows.add(_toEntry(c.raw, c.categoryId, c.hash, now, moveBalance: moveBalances));
    }
    final inserted = await _transactions.insertMany(rows);
    await _alerts?.checkMonth(now);
    return ImportResult(inserted: inserted, skipped: skipped);
  }

  /// Saves one manually typed transaction. Manual entries are never
  /// rejected as duplicates (two identical coffees on one day are normal).
  Future<int> saveManual(RawTransaction raw) async {
    final r = normalize(raw);
    if (r.amount <= 0) throw ArgumentError('Amount must be greater than zero');
    if (r.kind == TransactionKind.transfer && r.cardId == r.toCardId) {
      throw ArgumentError('A transfer needs two different accounts');
    }
    // Transfers aren't spending, so they don't get a category. Keyword
    // rules point at expense categories, so income falls back to "Other income".
    final categoryId = switch (r.kind) {
      TransactionKind.transfer => null,
      TransactionKind.income => r.categoryId ?? await _categories?.otherIncomeId(),
      TransactionKind.expense => r.categoryId ?? (await _categorizer()).categorize(r.description),
      TransactionKind.savings => r.categoryId ?? await _categories?.savingsCategoryId(),
    };
    final id = await _transactions.insert(_toEntry(r, categoryId, hashOf(r), _clock()));
    await _alerts?.checkMonth(r.date);
    return id;
  }

  /// Suggests a category for a description (used by the add form).
  Future<int?> suggestCategory(String description) async =>
      (await _categorizer()).match(description)?.categoryId;

  RawTransaction normalize(RawTransaction raw) {
    var d = raw.description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (d.isEmpty) d = 'Unknown';
    if (d.length > maxDescriptionLength) d = d.substring(0, maxDescriptionLength);
    return raw.copyWith(description: d, amount: raw.amount.abs());
  }

  static String hashOf(RawTransaction r) => Deduplicator.hashFor(
        date: r.date,
        amount: r.amount,
        kind: r.kind,
        description: r.description,
        cardId: r.cardId,
      );

  Future<AutoCategorizer> _categorizer() async =>
      AutoCategorizer(await _rules.all(), fallbackCategoryId: DefaultData.other);

  TransactionEntry _toEntry(RawTransaction r, int? categoryId, String hash, DateTime now, {bool moveBalance = false}) =>
      TransactionEntry(
        amount: r.amount,
        kind: r.kind,
        description: r.description,
        categoryId: categoryId,
        customCategory: r.customCategory,
        cardId: r.cardId,
        toCardId: r.toCardId,
        date: r.date,
        notes: r.notes,
        source: r.source,
        externalId: r.externalId,
        dedupHash: hash,
        // Typed entries move the account balance. Imported statement / SMS
        // rows don't: the starting balance the user typed already includes
        // them, so counting them again would take the money out twice.
        affectsBalance: moveBalance || r.source == TransactionSourceType.manual,
        savingsAction: r.savingsAction,
        createdAt: now,
        updatedAt: now,
      );
}
