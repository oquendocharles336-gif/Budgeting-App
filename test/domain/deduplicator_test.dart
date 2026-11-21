import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/domain/import/deduplicator.dart';
import 'package:flutter_test/flutter_test.dart';

String h(String desc, {int amount = 25000, int? cardId = 1, DateTime? date}) => Deduplicator.hashFor(
      date: date ?? DateTime(2026, 11, 20, 9, 30),
      amount: amount,
      kind: TransactionKind.expense,
      description: desc,
      cardId: cardId,
    );

void main() {
  group('hashFor', () {
    test('ignores case, punctuation, spacing and time of day', () {
      expect(h('JOLLIBEE - SM North!!'), h('jollibee   sm north'));
      expect(h('x', date: DateTime(2026, 11, 20, 1)), h('x', date: DateTime(2026, 11, 20, 23, 59)));
    });

    test('changes with amount, day, card or description', () {
      expect(h('x'), isNot(h('x', amount: 25001)));
      expect(h('x'), isNot(h('x', date: DateTime(2026, 11, 21))));
      expect(h('x'), isNot(h('x', cardId: 2)));
      expect(h('x'), isNot(h('x', cardId: null)));
      expect(h('x'), isNot(h('y')));
    });
  });

  group('findDuplicates', () {
    test('external id matches are scoped per card', () {
      final r = Deduplicator.findDuplicates(
        const [
          DedupKey(hash: 'h1', cardId: 1, externalId: 'csv:R1'),
          DedupKey(hash: 'h2', cardId: 2, externalId: 'csv:R1'),
        ],
        existingExternalIds: {DedupKey.scopeExternalId(1, 'csv:R1')},
        existingHashCounts: const {},
      );
      expect(r, [DuplicateReason.externalId, null]);
    });

    test('hash matches are counted: genuine repeats survive a re-import', () {
      // Database already has one copy; the file has three identical rows.
      final r = Deduplicator.findDuplicates(
        const [
          DedupKey(hash: 'h', cardId: 1),
          DedupKey(hash: 'h', cardId: 1),
          DedupKey(hash: 'h', cardId: 1),
        ],
        existingExternalIds: const {},
        existingHashCounts: const {'h': 1},
      );
      expect(r, [DuplicateReason.sameDetails, null, null]);
    });

    test('same external id twice in one batch', () {
      final r = Deduplicator.findDuplicates(
        const [
          DedupKey(hash: 'a', cardId: 1, externalId: 'sms:9'),
          DedupKey(hash: 'b', cardId: 1, externalId: 'sms:9'),
        ],
        existingExternalIds: const {},
        existingHashCounts: const {},
      );
      expect(r, [null, DuplicateReason.externalId]);
    });

    test('an external-id match also uses up its saved hash', () {
      final r = Deduplicator.findDuplicates(
        const [
          DedupKey(hash: 'a', cardId: 1, externalId: 'x'),
          DedupKey(hash: 'a', cardId: 1),
        ],
        existingExternalIds: {DedupKey.scopeExternalId(1, 'x')},
        existingHashCounts: const {'a': 1},
      );
      expect(r, [DuplicateReason.externalId, null]);
    });

    test('nothing saved yet -> nothing is a duplicate', () {
      final r = Deduplicator.findDuplicates(
        const [DedupKey(hash: 'a', cardId: null), DedupKey(hash: 'b', cardId: null)],
        existingExternalIds: const {},
        existingHashCounts: const {},
      );
      expect(r, [null, null]);
    });
  });
}
