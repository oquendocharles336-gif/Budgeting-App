import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/dates.dart';
import '../../core/text_normalize.dart';
import '../../data/models/transaction_entry.dart';

/// What the de-duplicator needs to know about one incoming transaction.
class DedupKey {
  const DedupKey({required this.hash, required this.cardId, this.externalId});

  final String hash;
  final int? cardId;
  final String? externalId;

  String? get scopedExternalId => externalId == null ? null : scopeExternalId(cardId, externalId!);

  static String scopeExternalId(int? cardId, String externalId) =>
      '${cardId ?? 'cash'}|$externalId';
}

enum DuplicateReason { externalId, sameDetails }

/// Detects transactions that are already saved.
///
/// Two checks, in order:
///  1. Same card + same external ID (SMS id, statement reference).
///  2. Same card + day + amount + kind + normalized description (the hash).
///
/// The hash check counts occurrences, so two genuine identical purchases on
/// the same day survive a re-import: if the database already has 1 copy and
/// the file has 2, only the first copy in the file is flagged.
class Deduplicator {
  Deduplicator._();

  static String hashFor({
    required DateTime date,
    required int amount,
    required TransactionKind kind,
    required String description,
    int? cardId,
  }) {
    final key = [
      'v1',
      cardId?.toString() ?? 'cash',
      Dates.dayKey(date),
      kind.name,
      amount.toString(),
      normalizeText(description),
    ].join('|');
    return sha256.convert(utf8.encode(key)).toString();
  }

  /// Returns a reason for each candidate, or null when it is new.
  ///
  /// [existingExternalIds] holds scoped IDs (see [DedupKey.scopeExternalId]).
  /// [existingHashCounts] maps hash -> number of saved rows with that hash.
  static List<DuplicateReason?> findDuplicates(
    List<DedupKey> candidates, {
    required Set<String> existingExternalIds,
    required Map<String, int> existingHashCounts,
  }) {
    final seenExternal = {...existingExternalIds};
    final remaining = {...existingHashCounts};
    final result = <DuplicateReason?>[];

    for (final c in candidates) {
      final ext = c.scopedExternalId;
      if (ext != null && seenExternal.contains(ext)) {
        // Consume one matching hash too, so the saved copy isn't counted twice.
        final left = remaining[c.hash] ?? 0;
        if (left > 0) remaining[c.hash] = left - 1;
        result.add(DuplicateReason.externalId);
        continue;
      }
      final left = remaining[c.hash] ?? 0;
      if (left > 0) {
        remaining[c.hash] = left - 1;
        result.add(DuplicateReason.sameDetails);
        continue;
      }
      if (ext != null) seenExternal.add(ext);
      result.add(null);
    }
    return result;
  }
}
