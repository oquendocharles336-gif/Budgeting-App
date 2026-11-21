import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/domain/analytics/data_prep.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> row({
  Object? id,
  Object? amount = 15000,
  Object? date,
  Object? description = 'Jollibee',
  Object? category = 1,
  Object? kind = 'expense',
  Object? card,
  String source = 'manual',
}) =>
    {
      'id': id,
      'amount': amount,
      'date': date ?? DateTime(2026, 11, 3, 12).millisecondsSinceEpoch,
      'description': description,
      'category_id': category,
      'kind': kind,
      'card_id': card,
      'source': source,
    };

void main() {
  group('missing values', () {
    test('rows without amount or date are skipped, never a crash', () {
      final out = DataPrep.clean([
        row(id: 1),
        row(id: 2, amount: null),
        row(id: 3, amount: ''),
        row(id: 4, amount: 'abc'),
        row(id: 5, amount: 0),
        row(id: 6, date: 'not a date'),
        {'id': 7}, // almost everything missing
      ]);
      expect(out.rows.map((t) => t.id), [1]);
      expect(out.report.checked, 7);
      expect(out.report.droppedMissingAmount, 5);
      expect(out.report.droppedMissingDate, 1);
    });

    test('missing or unknown category becomes Uncategorized (null)', () {
      final out = DataPrep.clean(
        [row(id: 1, category: null), row(id: 2, category: 99), row(id: 3, category: 1)],
        knownCategoryIds: {1},
      );
      expect(out.rows.map((t) => t.categoryId), [null, null, 1]);
      expect(out.report.uncategorized, 2);
    });

    test('empty description becomes Unknown; unknown kind is an expense', () {
      final out = DataPrep.clean([row(id: 1, description: '   ', kind: 'weird')]);
      expect(out.rows.single.description, 'Unknown');
      expect(out.rows.single.kind, TransactionKind.expense);
    });
  });

  group('normalizing', () {
    test('amounts from text, doubles and negatives become positive centavos', () {
      final out = DataPrep.clean([
        row(id: 1, amount: '₱1,234.50'),
        row(id: 2, amount: -500),
        row(id: 3, amount: 250.0),
      ]);
      expect(out.rows.map((t) => t.amount), [123450, 500, 250]);
    });

    test('dates from ISO text and text milliseconds; text trimmed and single-spaced', () {
      final ms = DateTime(2026, 1, 5).millisecondsSinceEpoch;
      final out = DataPrep.clean([
        row(id: 1, date: '2026-01-05T08:30:00', description: '  Grab   Food  '),
        row(id: 2, date: '$ms'),
      ]);
      expect(out.rows[0].date, DateTime(2026, 1, 5, 8, 30));
      expect(out.rows[0].description, 'Grab Food');
      expect(out.rows[1].date, DateTime(2026, 1, 5));
    });
  });

  group('duplicates', () {
    test('an imported copy of the same amount, day, description and account is removed', () {
      final out = DataPrep.clean([
        row(id: 1, card: 3, description: 'GRAB FOOD'),
        row(id: 2, card: 3, description: 'grab food', source: 'csv_import',
            date: DateTime(2026, 11, 3, 20).millisecondsSinceEpoch),
        row(id: 3, card: 3, description: 'grab food', source: 'sms_parsed'),
      ]);
      expect(out.rows.map((t) => t.id), [1]);
      expect(out.report.duplicatesRemoved, 2);
      expect(out.report.summary, contains('removed 2 duplicates'));
    });

    test('different account, day or amount is not a duplicate', () {
      final out = DataPrep.clean([
        row(id: 1, card: 3, source: 'csv_import'),
        row(id: 2, card: 4, source: 'csv_import'),
        row(id: 3, card: 3, source: 'csv_import', amount: 15001),
        row(id: 4, card: 3, source: 'csv_import', date: DateTime(2026, 11, 4).millisecondsSinceEpoch),
      ]);
      expect(out.rows, hasLength(4));
      expect(out.report.duplicatesRemoved, 0);
    });

    test('identical manual entries are kept (two coffees are real)', () {
      final out = DataPrep.clean([row(id: 1), row(id: 2)]);
      expect(out.rows, hasLength(2));
      final strict = DataPrep.clean([row(id: 1), row(id: 2)], keepManualRepeats: false);
      expect(strict.rows, hasLength(1));
    });
  });
}
