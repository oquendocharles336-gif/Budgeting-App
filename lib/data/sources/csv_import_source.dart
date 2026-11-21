import '../../domain/csv/csv_parser.dart';
import '../models/payment_card.dart';
import '../models/raw_transaction.dart';
import '../models/transaction_entry.dart';
import 'transaction_source.dart';

/// Reads a card statement exported as CSV.
///
/// The import screen loads the file, lets the user map columns, then calls
/// [fetchTransactions]. Rows that couldn't be read are kept in [rowErrors]
/// so the preview can show them.
class CsvImportSource implements TransactionSource {
  CsvImportSource({required this.rows, required this.mapping});

  /// Builds a source from raw file text.
  factory CsvImportSource.fromText(String text, CsvMapping mapping, {String? delimiter}) =>
      CsvImportSource(rows: CsvParser.parse(text, delimiter: delimiter), mapping: mapping);

  final List<List<String>> rows;
  final CsvMapping mapping;
  List<CsvRowResult> rowErrors = const [];

  @override
  String get id => TransactionSourceType.csvImport.dbValue;

  @override
  String get displayName => 'CSV statement';

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<RawTransaction>> fetchTransactions({
    required PaymentCard card,
    DateTime? since,
  }) async {
    final results = CsvStatementReader.read(rows, mapping, cardId: card.id);
    rowErrors = results.where((r) => !r.isValid).toList();
    return [
      for (final r in results)
        if (r.transaction != null && (since == null || !r.transaction!.date.isBefore(since)))
          r.transaction!,
    ];
  }
}
