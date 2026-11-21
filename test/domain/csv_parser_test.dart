import 'package:budgeting_app/core/money.dart';
import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/domain/csv/csv_parser.dart';
import 'package:budgeting_app/domain/csv/date_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('plain and formatted amounts', () {
      expect(Money.parse('1,234.56'), 123456);
      expect(Money.parse('₱1,234.56'), 123456);
      expect(Money.parse('PHP 99'), 9900);
      expect(Money.parse('0.5'), 50);
      expect(Money.parse('1.'), 100);
    });

    test('negative forms', () {
      expect(Money.parse('-50'), -5000);
      expect(Money.parse('(50.00)'), -5000);
      expect(Money.parse('100.00 CR'), -10000);
      expect(Money.parse('₱-75.25'), -7525);
    });

    test('rounds half up to centavos', () {
      expect(Money.parse('12.345'), 1235);
      expect(Money.parse('12.344'), 1234);
    });

    test('decimal comma', () {
      expect(Money.parse('1.234,56', decimalComma: true), 123456);
    });

    test('invalid input returns null', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('1.2.3'), isNull);
    });
  });

  group('DateParser', () {
    test('ISO and numeric formats', () {
      expect(DateParser.parse('2026-11-20'), DateTime(2026, 11, 20));
      expect(DateParser.parse('2026/11/20 14:33'), DateTime(2026, 11, 20));
      expect(DateParser.parse('11/20/2026'), DateTime(2026, 11, 20));
      expect(DateParser.parse('20/11/2026'), DateTime(2026, 11, 20)); // auto: 20 can't be a month
      expect(DateParser.parse('11-20-26'), DateTime(2026, 11, 20));
    });

    test('ambiguous dates follow the chosen order', () {
      expect(DateParser.parse('03/04/2026', order: DateOrder.mdy), DateTime(2026, 3, 4));
      expect(DateParser.parse('03/04/2026', order: DateOrder.dmy), DateTime(2026, 4, 3));
    });

    test('month names', () {
      expect(DateParser.parse('Nov 20, 2026'), DateTime(2026, 11, 20));
      expect(DateParser.parse('20 Nov 2026'), DateTime(2026, 11, 20));
      expect(DateParser.parse('20-Nov-26'), DateTime(2026, 11, 20));
      expect(DateParser.parse('November 3rd 2026'), DateTime(2026, 11, 3));
    });

    test('invalid dates', () {
      expect(DateParser.parse('2026-02-30'), isNull);
      expect(DateParser.parse('13/13/2026'), isNull);
      expect(DateParser.parse('hello'), isNull);
    });
  });

  group('CsvParser.parse', () {
    test('quoted fields, commas inside quotes, escaped quotes, CRLF', () {
      const text = 'Date,Description,Amount\r\n'
          '2026-11-01,"JOLLIBEE, SM NORTH",250.00\r\n'
          '2026-11-02,"He said ""hi""",-1000\r\n';
      expect(CsvParser.parse(text), [
        ['Date', 'Description', 'Amount'],
        ['2026-11-01', 'JOLLIBEE, SM NORTH', '250.00'],
        ['2026-11-02', 'He said "hi"', '-1000'],
      ]);
    });

    test('line break inside quotes stays in the field', () {
      expect(CsvParser.parse('a,"line1\nline2",c\n'), [
        ['a', 'line1\nline2', 'c'],
      ]);
    });

    test('BOM, semicolon detection, blank lines, no trailing newline', () {
      expect(CsvParser.parse('﻿a;b\n\n1;2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('empty trailing field is kept', () {
      expect(CsvParser.parse('a,b,\n'), [
        ['a', 'b', ''],
      ]);
    });

    test('detects tab delimiter', () {
      expect(CsvParser.detectDelimiter('Date\tDesc\tAmount\n'), '\t');
    });
  });

  group('CsvMapping.guess', () {
    test('finds common header names', () {
      final m = CsvMapping.guess(['Transaction Date', 'Description', 'Amount', 'Reference No'])!;
      expect(m.dateColumn, 0);
      expect(m.descriptionColumn, 1);
      expect(m.amountColumn, 2);
      expect(m.referenceColumn, 3);
      expect(m.usesDebitCredit, isFalse);
    });

    test('debit/credit statements', () {
      final m = CsvMapping.guess(['Date', 'Particulars', 'Debit', 'Credit'])!;
      expect(m.usesDebitCredit, isTrue);
      expect(m.debitColumn, 2);
      expect(m.creditColumn, 3);
    });

    test('returns null without the needed columns', () {
      expect(CsvMapping.guess(['Foo', 'Bar']), isNull);
    });
  });

  group('CsvStatementReader', () {
    test('single amount column, charges positive', () {
      final rows = CsvParser.parse(
        'Date,Description,Amount\n'
        '2026-11-01,JOLLIBEE,250.00\n'
        '2026-11-02,PAYMENT - THANK YOU,-1000\n',
      );
      final result = CsvStatementReader.read(
        rows,
        const CsvMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2),
        cardId: 7,
      );
      expect(result.length, 2);
      final a = result[0].transaction!;
      expect(a.amount, 25000);
      expect(a.kind, TransactionKind.expense);
      expect(a.cardId, 7);
      expect(a.source, TransactionSourceType.csvImport);
      final b = result[1].transaction!;
      expect(b.amount, 100000);
      expect(b.kind, TransactionKind.income);
    });

    test('charges negative convention', () {
      final rows = CsvParser.parse('Date,Desc,Amt\n2026-11-01,GRAB,-150.50\n');
      final r = CsvStatementReader.read(
        rows,
        const CsvMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2, chargesArePositive: false),
      );
      expect(r.single.transaction!.kind, TransactionKind.expense);
      expect(r.single.transaction!.amount, 15050);
    });

    test('debit/credit columns and reference -> external id', () {
      final rows = CsvParser.parse(
        'Date,Details,Debit,Credit,Ref\n'
        '11/05/2026,SHOPEE,"1,299.00",,R1\n'
        '11/06/2026,PAYMENT THANK YOU,,5000.00,R2\n',
      );
      final r = CsvStatementReader.read(
        rows,
        const CsvMapping(dateColumn: 0, descriptionColumn: 1, debitColumn: 2, creditColumn: 3, referenceColumn: 4),
      );
      expect(r[0].transaction!.amount, 129900);
      expect(r[0].transaction!.kind, TransactionKind.expense);
      expect(r[0].transaction!.externalId, 'csv:R1');
      expect(r[0].transaction!.date, DateTime(2026, 11, 5));
      expect(r[1].transaction!.amount, 500000);
      expect(r[1].transaction!.kind, TransactionKind.income);
    });

    test('bad rows report a reason and a line number', () {
      final rows = CsvParser.parse(
        'Date,Description,Amount\n'
        'notadate,X,100\n'
        '2026-11-01,,100\n'
        '2026-11-01,Y,0.00\n'
        '2026-11-01,Z,abc\n',
      );
      final r = CsvStatementReader.read(rows, const CsvMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2));
      expect(r.every((x) => !x.isValid), isTrue);
      expect(r[0].rowNumber, 2);
      expect(r[0].error, contains('date'));
      expect(r[1].error, 'Missing description');
      expect(r[2].error, 'Amount is zero');
      expect(r[3].error, contains('amount'));
    });

    test('no header row', () {
      final rows = CsvParser.parse('2026-11-01,A,10\n2026-11-02,B,20\n');
      final r = CsvStatementReader.read(
        rows,
        const CsvMapping(dateColumn: 0, descriptionColumn: 1, amountColumn: 2, hasHeader: false),
      );
      expect(r.where((x) => x.isValid).length, 2);
    });
  });
}
