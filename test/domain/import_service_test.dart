import 'package:budgeting_app/data/db/default_data.dart';
import 'package:budgeting_app/data/models/category.dart';
import 'package:budgeting_app/data/models/payment_card.dart';
import 'package:budgeting_app/data/models/raw_transaction.dart';
import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/data/repositories/category_repository.dart';
import 'package:budgeting_app/data/repositories/transaction_repository.dart';
import 'package:budgeting_app/data/sources/bank_sync_source.dart';
import 'package:budgeting_app/data/sources/csv_import_source.dart';
import 'package:budgeting_app/data/sources/transaction_source.dart';
import 'package:budgeting_app/domain/csv/csv_parser.dart';
import 'package:budgeting_app/domain/import/deduplicator.dart';
import 'package:budgeting_app/domain/import/transaction_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the SQLite repository.
class FakeTransactionRepository implements TransactionRepository {
  final rows = <TransactionEntry>[];

  @override
  Future<int> insert(TransactionEntry tx) async {
    rows.add(tx);
    return rows.length;
  }

  @override
  Future<int> insertMany(List<TransactionEntry> txs) async {
    rows.addAll(txs);
    return txs.length;
  }

  @override
  Future<Set<String>> existingExternalIds(Iterable<int?> cardIds) async {
    final ids = cardIds.toSet();
    return {
      for (final r in rows)
        if (r.externalId != null && ids.contains(r.cardId)) DedupKey.scopeExternalId(r.cardId, r.externalId!),
    };
  }

  @override
  Future<Map<String, int>> hashCounts(Iterable<String> hashes) async {
    final wanted = hashes.toSet();
    final out = <String, int>{};
    for (final r in rows) {
      if (r.dedupHash != null && wanted.contains(r.dedupHash)) {
        out[r.dedupHash!] = (out[r.dedupHash!] ?? 0) + 1;
      }
    }
    return out;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRuleRepository implements RuleRepository {
  FakeRuleRepository(this.rules);
  final List<CategoryRule> rules;

  @override
  Future<List<CategoryRule>> all() async => rules;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeTransactionRepository repo;
  late TransactionImportService service;
  final card = PaymentCard(
    id: 1,
    nickname: 'BDO',
    last4: '1234',
    type: CardType.credit,
    color: 0xFF000000,
    createdAt: DateTime(2026),
  );

  const csv = 'Date,Description,Amount\n'
      '2026-11-01,JOLLIBEE SM NORTH,250.00\n'
      '2026-11-02,STARBUCKS,180.00\n'
      '2026-11-02,STARBUCKS,180.00\n' // genuinely bought twice
      '2026-11-03,UNKNOWN SHOP,99.00\n';
  const mapping = CsvMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2);

  setUp(() {
    repo = FakeTransactionRepository();
    service = TransactionImportService(
      transactions: repo,
      rules: FakeRuleRepository(const [
        CategoryRule(keyword: 'jollibee', categoryId: DefaultData.food),
        CategoryRule(keyword: 'starbucks', categoryId: DefaultData.food),
      ]),
      clock: () => DateTime(2026, 11, 21),
    );
  });

  test('CSV import: categorize, save, then re-import skips everything', () async {
    final first = await service.preview(CsvImportSource.fromText(csv, mapping), card: card);
    expect(first.length, 4);
    expect(first.every((c) => !c.isDuplicate && c.selected), isTrue);
    expect(first[0].categoryId, DefaultData.food);
    expect(first[3].categoryId, DefaultData.other); // no rule -> fallback

    final saved = await service.commit(first);
    expect(saved.inserted, 4);
    expect(repo.rows.every((r) => r.source == TransactionSourceType.csvImport && r.cardId == 1), isTrue);

    // Same file again: every row is flagged and unticked.
    final again = await service.preview(CsvImportSource.fromText(csv, mapping), card: card);
    expect(again.every((c) => c.duplicate == DuplicateReason.sameDetails && !c.selected), isTrue);
    final result = await service.commit(again);
    expect(result.inserted, 0);
    expect(result.skipped, 4);
    expect(repo.rows.length, 4);
  });

  test('a longer statement only adds the new rows', () async {
    await service.commit(await service.preview(CsvImportSource.fromText(csv, mapping), card: card));
    const longer = '${csv}2026-11-04,MERCURY DRUG,320.00\n';
    final next = await service.preview(CsvImportSource.fromText(longer, mapping), card: card);
    expect(next.where((c) => !c.isDuplicate).map((c) => c.raw.description), ['MERCURY DRUG']);
    final r = await service.commit(next);
    expect(r.inserted, 1);
    expect(repo.rows.length, 5);
  });

  test('rows with an external id can never be saved twice, even if re-ticked', () async {
    final raws = [
      RawTransaction(
        date: DateTime(2026, 11, 5),
        description: 'SHOPEE',
        amount: 50000,
        source: TransactionSourceType.smsParsed,
        cardId: 1,
        externalId: 'sms:77',
      ),
    ];
    await service.commit(await service.prepare(raws));
    final again = await service.prepare(raws);
    expect(again.single.duplicate, DuplicateReason.externalId);
    again.single.selected = true; // user insists
    final r = await service.commit(again);
    expect(r.inserted, 0);
    expect(repo.rows.length, 1);
  });

  test('manual entries are never treated as duplicates', () async {
    final coffee = RawTransaction(
      date: DateTime(2026, 11, 6, 8),
      description: '  Coffee   ',
      amount: 15000,
      source: TransactionSourceType.manual,
    );
    await service.saveManual(coffee);
    await service.saveManual(coffee);
    expect(repo.rows.length, 2);
    expect(repo.rows.first.description, 'Coffee'); // normalized
    expect(repo.rows.first.isCash, isTrue);
  });

  test('bank sync placeholder is unavailable', () async {
    const source = BankSyncSource();
    expect(await source.isAvailable(), isFalse);
    expect(source.requiresNetwork, isTrue);
    await expectLater(service.preview(source, card: card), throwsA(isA<SourceUnavailableException>()));
  });
}
