import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/transaction_entry.dart';

/// What the cleaning step did, for the inline "Checked 120 transactions ·
/// removed 6 duplicates" line.
class PrepReport {
  const PrepReport({
    required this.checked,
    required this.kept,
    required this.droppedMissingAmount,
    required this.droppedMissingDate,
    required this.uncategorized,
    required this.duplicatesRemoved,
  });

  static const empty = PrepReport(
    checked: 0,
    kept: 0,
    droppedMissingAmount: 0,
    droppedMissingDate: 0,
    uncategorized: 0,
    duplicatesRemoved: 0,
  );

  final int checked;
  final int kept;
  final int droppedMissingAmount;
  final int droppedMissingDate;

  /// Kept, but filed under "Uncategorized" (no or unknown category).
  final int uncategorized;
  final int duplicatesRemoved;

  int get dropped => droppedMissingAmount + droppedMissingDate;
  bool get changedAnything => dropped > 0 || duplicatesRemoved > 0 || uncategorized > 0;

  /// One short line, e.g. "Checked 120 transactions · removed 6 duplicates".
  String get summary {
    final parts = <String>['Checked $checked transaction${checked == 1 ? '' : 's'}'];
    if (duplicatesRemoved > 0) parts.add('removed $duplicatesRemoved duplicate${duplicatesRemoved == 1 ? '' : 's'}');
    if (dropped > 0) parts.add('skipped $dropped with no amount or date');
    if (uncategorized > 0) parts.add('$uncategorized uncategorized');
    return parts.join(' · ');
  }
}

class PreparedData {
  const PreparedData(this.rows, this.report);
  final List<TransactionEntry> rows;
  final PrepReport report;
}

/// The data-prep step that runs before any chart or total.
///
/// 1. **Missing values**: a row with no usable amount or date can't be
///    counted, so it is skipped (never a crash). No / unknown category is
///    kept as "Uncategorized" (category id null). Empty description becomes
///    "Unknown".
/// 2. **Normalize**: amounts to positive integer centavos (from int, double
///    or text like "₱1,234.50"), dates from epoch ms or ISO text, trimmed
///    and single-spaced text, unknown kinds as expense.
/// 3. **Duplicates**: rows with the same kind, amount, day, description
///    (case-insensitive) and account. If any copy came from a CSV / SMS /
///    bank import, only the first is kept. Copies that were all typed by
///    hand are kept: two identical coffees on one day are real spending.
///
/// Pure function: no database, easy to unit test.
class DataPrep {
  DataPrep._();

  static const uncategorizedLabel = 'Uncategorized';

  /// Cleans raw `transactions` rows (maps straight from SQLite or a file).
  /// [knownCategoryIds]: when given, ids not in it count as uncategorized.
  static PreparedData clean(
    Iterable<Map<String, Object?>> raw, {
    Set<int>? knownCategoryIds,
    bool keepManualRepeats = true,
  }) {
    var checked = 0, noAmount = 0, noDate = 0, uncategorized = 0, syntheticId = -1;
    final normalized = <TransactionEntry>[];
    for (final row in raw) {
      checked++;
      final amount = parseAmount(row['amount']);
      if (amount == null || amount == 0) {
        noAmount++;
        continue;
      }
      final date = parseDate(row['date']);
      if (date == null) {
        noDate++;
        continue;
      }
      var categoryId = _asInt(row['category_id']);
      if (categoryId != null && knownCategoryIds != null && !knownCategoryIds.contains(categoryId)) {
        categoryId = null;
      }
      final kind = TransactionKind.fromDb(_text(row['kind']) ?? 'expense');
      if (categoryId == null && kind != TransactionKind.transfer) uncategorized++;
      final created = parseDate(row['created_at']) ?? date;
      normalized.add(TransactionEntry(
        id: _asInt(row['id']) ?? syntheticId--,
        amount: amount.abs(),
        kind: kind,
        description: normalizeText(_text(row['description'])) ?? 'Unknown',
        categoryId: categoryId,
        customCategory: normalizeText(_text(row['custom_category'])),
        cardId: _asInt(row['card_id']),
        toCardId: _asInt(row['to_card_id']),
        date: date,
        notes: normalizeText(_text(row['notes'])),
        source: TransactionSourceType.fromDb(_text(row['source']) ?? 'manual'),
        externalId: normalizeText(_text(row['external_id'])),
        dedupHash: _text(row['dedup_hash']),
        affectsBalance: _asInt(row['affects_balance']) == 1,
        debtId: _asInt(row['debt_id']),
        createdAt: created,
        updatedAt: parseDate(row['updated_at']) ?? created,
      ));
    }
    final (rows, removed) = removeDuplicates(normalized, keepManualRepeats: keepManualRepeats);
    return PreparedData(
      rows,
      PrepReport(
        checked: checked,
        kept: rows.length,
        droppedMissingAmount: noAmount,
        droppedMissingDate: noDate,
        uncategorized: uncategorized - _uncategorizedAmong(normalized, rows),
        duplicatesRemoved: removed,
      ),
    );
  }

  static int _uncategorizedAmong(List<TransactionEntry> all, List<TransactionEntry> kept) {
    final keptIds = {for (final t in kept) t.id};
    return all.where((t) => !keptIds.contains(t.id) && t.categoryId == null && !t.isTransfer).length;
  }

  /// Duplicate key: kind, amount, calendar day, description, accounts.
  static String duplicateKey(TransactionEntry t) => [
        t.kind.name,
        t.amount,
        Dates.dayKey(t.date),
        t.description.toLowerCase(),
        t.cardId ?? 'cash',
        t.toCardId ?? '-',
      ].join('|');

  /// Returns the rows without duplicates (original order) and how many were removed.
  static (List<TransactionEntry>, int) removeDuplicates(
    List<TransactionEntry> rows, {
    bool keepManualRepeats = true,
  }) {
    final groups = <String, List<TransactionEntry>>{};
    for (final t in rows) {
      groups.putIfAbsent(duplicateKey(t), () => []).add(t);
    }
    final drop = <TransactionEntry>{};
    for (final g in groups.values) {
      if (g.length < 2) continue;
      final anyImported = g.any((t) => t.source != TransactionSourceType.manual);
      if (keepManualRepeats && !anyImported) continue;
      // Keep the oldest saved row (lowest id), drop the rest.
      final sorted = [...g]..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
      drop.addAll(sorted.skip(1));
    }
    if (drop.isEmpty) return (rows, 0);
    return ([for (final t in rows) if (!drop.contains(t)) t], drop.length);
  }

  /// Positive or negative centavos, or null if missing / unreadable.
  static int? parseAmount(Object? v) => switch (v) {
        null => null,
        int i => i,
        // Amounts are stored as integer centavos; a REAL is rounded to one.
        double d => d.isFinite ? d.round() : null,
        String s => Money.parse(s),
        _ => null,
      };

  static DateTime? parseDate(Object? v) => switch (v) {
        null => null,
        int ms => ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
        String s => int.tryParse(s.trim()) != null
            ? parseDate(int.parse(s.trim()))
            : DateTime.tryParse(s.trim()),
        DateTime d => d,
        _ => null,
      };

  /// Trimmed, single-spaced; null when empty.
  static String? normalizeText(String? s) {
    if (s == null) return null;
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? null : t;
  }

  static int? _asInt(Object? v) => switch (v) {
        int i => i,
        double d when d.isFinite => d.round(),
        String s => int.tryParse(s.trim()),
        _ => null,
      };

  static String? _text(Object? v) => v?.toString();
}
