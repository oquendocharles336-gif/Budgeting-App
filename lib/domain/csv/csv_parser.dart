import '../../core/money.dart';
import '../../data/models/raw_transaction.dart';
import '../../data/models/transaction_entry.dart';
import 'date_parser.dart';

/// Splits CSV text into rows of cells.
///
/// Handles quoted fields, escaped quotes (""), delimiters and line breaks
/// inside quotes, CRLF/LF/CR line endings and a UTF-8 BOM.
class CsvParser {
  CsvParser._();

  static List<List<String>> parse(String text, {String? delimiter}) {
    var input = text;
    if (input.startsWith('﻿')) input = input.substring(1);
    final delim = delimiter ?? detectDelimiter(input);
    if (delim.length != 1) {
      throw ArgumentError.value(delimiter, 'delimiter', 'must be one character');
    }
    final d = delim.codeUnitAt(0);
    const quote = 0x22; // "
    const cr = 0x0D;
    const lf = 0x0A;

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;
    final n = input.length;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      // Drop rows that are completely blank.
      if (!(row.length == 1 && row.first.trim().isEmpty)) rows.add(row);
      row = <String>[];
    }

    while (i < n) {
      final c = input.codeUnitAt(i);
      if (inQuotes) {
        if (c == quote) {
          if (i + 1 < n && input.codeUnitAt(i + 1) == quote) {
            field.writeCharCode(quote);
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.writeCharCode(c);
        i++;
        continue;
      }
      if (c == quote && field.isEmpty) {
        inQuotes = true;
        i++;
      } else if (c == d) {
        endField();
        i++;
      } else if (c == cr || c == lf) {
        endRow();
        // Treat CRLF as one line break.
        if (c == cr && i + 1 < n && input.codeUnitAt(i + 1) == lf) i++;
        i++;
      } else {
        field.writeCharCode(c);
        i++;
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  /// Picks the most common of , ; tab | in the first line.
  static String detectDelimiter(String text) {
    final firstLine = text.split(RegExp(r'\r?\n')).first;
    const candidates = [',', ';', '\t', '|'];
    var best = ',';
    var bestCount = 0;
    for (final c in candidates) {
      final count = c.allMatches(firstLine).length;
      if (count > bestCount) {
        best = c;
        bestCount = count;
      }
    }
    return best;
  }
}

/// Which CSV columns hold which fields. Column indexes are 0-based.
class CsvMapping {
  const CsvMapping({
    required this.dateColumn,
    required this.descriptionColumn,
    this.amountColumn,
    this.debitColumn,
    this.creditColumn,
    this.referenceColumn,
    this.hasHeader = true,
    this.dateOrder = DateOrder.auto,
    this.chargesArePositive = true,
    this.decimalComma = false,
  });

  final int dateColumn;
  final int descriptionColumn;

  /// Single signed amount column.
  final int? amountColumn;

  /// Alternative to [amountColumn]: separate debit (money out) and
  /// credit (money in) columns.
  final int? debitColumn;
  final int? creditColumn;

  /// Optional statement reference / transaction ID, used for de-duplication.
  final int? referenceColumn;
  final bool hasHeader;
  final DateOrder dateOrder;

  /// For a single amount column: true when purchases are positive numbers
  /// and payments/refunds are negative (typical for card statements).
  final bool chargesArePositive;
  final bool decimalComma;

  bool get usesDebitCredit => amountColumn == null;

  CsvMapping copyWith({
    int? dateColumn,
    int? descriptionColumn,
    int? Function()? amountColumn,
    int? Function()? debitColumn,
    int? Function()? creditColumn,
    int? Function()? referenceColumn,
    bool? hasHeader,
    DateOrder? dateOrder,
    bool? chargesArePositive,
    bool? decimalComma,
  }) =>
      CsvMapping(
        dateColumn: dateColumn ?? this.dateColumn,
        descriptionColumn: descriptionColumn ?? this.descriptionColumn,
        amountColumn: amountColumn != null ? amountColumn() : this.amountColumn,
        debitColumn: debitColumn != null ? debitColumn() : this.debitColumn,
        creditColumn: creditColumn != null ? creditColumn() : this.creditColumn,
        referenceColumn: referenceColumn != null ? referenceColumn() : this.referenceColumn,
        hasHeader: hasHeader ?? this.hasHeader,
        dateOrder: dateOrder ?? this.dateOrder,
        chargesArePositive: chargesArePositive ?? this.chargesArePositive,
        decimalComma: decimalComma ?? this.decimalComma,
      );

  /// Guesses a mapping from header names like "Date", "Description", "Amount".
  static CsvMapping? guess(List<String> header) {
    int? find(List<String> names) {
      for (var i = 0; i < header.length; i++) {
        final h = header[i].toLowerCase().trim();
        if (names.any((n) => h == n || h.contains(n))) return i;
      }
      return null;
    }

    final date = find(['transaction date', 'trans date', 'posting date', 'post date', 'date']);
    final desc = find(['description', 'details', 'merchant', 'particulars', 'narrative', 'payee', 'memo']);
    final amount = find(['amount']);
    final debit = find(['debit', 'withdrawal', 'charge']);
    final credit = find(['credit', 'deposit', 'payment']);
    final ref = find(['reference', 'ref no', 'ref', 'transaction id', 'trans id']);
    if (date == null || desc == null) return null;
    if (amount == null && debit == null && credit == null) return null;
    return CsvMapping(
      dateColumn: date,
      descriptionColumn: desc,
      amountColumn: amount,
      debitColumn: amount == null ? debit : null,
      creditColumn: amount == null ? credit : null,
      referenceColumn: ref,
    );
  }
}

/// Result of reading one CSV row.
class CsvRowResult {
  const CsvRowResult({required this.rowNumber, required this.cells, this.transaction, this.error});

  /// 1-based line number in the file, for error messages.
  final int rowNumber;
  final List<String> cells;
  final RawTransaction? transaction;
  final String? error;

  bool get isValid => transaction != null;
}

/// Turns parsed CSV rows into [RawTransaction]s using a [CsvMapping].
class CsvStatementReader {
  CsvStatementReader._();

  static List<CsvRowResult> read(
    List<List<String>> rows,
    CsvMapping mapping, {
    int? cardId,
  }) {
    final results = <CsvRowResult>[];
    final start = mapping.hasHeader ? 1 : 0;
    for (var r = start; r < rows.length; r++) {
      results.add(_readRow(rows[r], r + 1, mapping, cardId));
    }
    return results;
  }

  static CsvRowResult _readRow(List<String> cells, int rowNumber, CsvMapping m, int? cardId) {
    String? cell(int? index) {
      if (index == null || index < 0 || index >= cells.length) return null;
      final v = cells[index].trim();
      return v.isEmpty ? null : v;
    }

    CsvRowResult fail(String message) =>
        CsvRowResult(rowNumber: rowNumber, cells: cells, error: message);

    final dateText = cell(m.dateColumn);
    if (dateText == null) return fail('Missing date');
    final date = DateParser.parse(dateText, order: m.dateOrder);
    if (date == null) return fail('Unreadable date "$dateText"');

    final description = cell(m.descriptionColumn);
    if (description == null) return fail('Missing description');

    int signed; // negative = money out
    if (!m.usesDebitCredit) {
      final text = cell(m.amountColumn);
      if (text == null) return fail('Missing amount');
      final v = Money.parse(text, decimalComma: m.decimalComma);
      if (v == null) return fail('Unreadable amount "$text"');
      signed = m.chargesArePositive ? -v : v;
    } else {
      if (m.debitColumn == null && m.creditColumn == null) return fail('Choose a debit or credit column');
      final debitText = cell(m.debitColumn);
      final creditText = cell(m.creditColumn);
      final debit = debitText == null ? 0 : Money.parse(debitText, decimalComma: m.decimalComma);
      final credit = creditText == null ? 0 : Money.parse(creditText, decimalComma: m.decimalComma);
      if (debit == null) return fail('Unreadable debit "$debitText"');
      if (credit == null) return fail('Unreadable credit "$creditText"');
      signed = credit.abs() - debit.abs();
    }
    if (signed == 0) return fail('Amount is zero');

    final ref = cell(m.referenceColumn);
    return CsvRowResult(
      rowNumber: rowNumber,
      cells: cells,
      transaction: RawTransaction(
        date: date,
        description: description,
        amount: signed.abs(),
        kind: signed < 0 ? TransactionKind.expense : TransactionKind.income,
        source: TransactionSourceType.csvImport,
        cardId: cardId,
        externalId: ref == null ? null : 'csv:$ref',
        originalText: cells.join(', '),
      ),
    );
  }
}
