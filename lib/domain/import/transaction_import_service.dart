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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository _transactions;
  final RuleRepository _rules;
  final BudgetAlertService? _alerts;
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
          categoryId: items[i].categoryId ?? categorizer.categorize(items[i].description),
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
  Future<ImportResult> commit(List<ImportCandidate> candidates) async {
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
      rows.add(_toEntry(c.raw, c.categoryId, c.hash, now));
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
    final categoryId = r.categoryId ?? (await _categorizer()).categorize(r.description);
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

  TransactionEntry _toEntry(RawTransaction r, int? categoryId, String hash, DateTime now) =>
      TransactionEntry(
        amount: r.amount,
        kind: r.kind,
        description: r.description,
        categoryId: categoryId,
        cardId: r.cardId,
        date: r.date,
        notes: r.notes,
        source: r.source,
        externalId: r.externalId,
        dedupHash: hash,
        createdAt: now,
        updatedAt: now,
      );
}
