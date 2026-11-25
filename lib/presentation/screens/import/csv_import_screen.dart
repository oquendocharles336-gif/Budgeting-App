import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/payment_card.dart';
import '../../../data/sources/csv_import_source.dart';
import '../../../domain/csv/csv_parser.dart';
import '../../../domain/csv/date_parser.dart';
import '../../../domain/import/transaction_import_service.dart';
import '../../../domain/services/app_lock_service.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/work_steps.dart';
import 'import_review.dart';

enum _Step { pick, map, review }

/// Pick CSV -> map columns (with live preview) -> review -> save.
class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key, required this.card});
  final PaymentCard card;

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  static const _maxRows = 5000;

  _Step _step = _Step.pick;
  String? _fileName;
  List<List<String>> _rows = const [];
  CsvMapping? _mapping;
  List<ImportCandidate> _candidates = const [];
  int _invalidRows = 0;
  bool _busy = false;
  String? _error;

  int get _columnCount => _rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Guarded: leaving for the picker must not lock the app.
      final file = await LockGuard.run(() => FilePicker.pickFile(
            type: FileType.custom,
            allowedExtensions: const ['csv', 'txt'],
            dialogTitle: 'Choose a CSV statement',
          ));
      if (file == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final rows = CsvParser.parse(text);
      if (rows.isEmpty) throw const FormatException('The file is empty.');
      if (rows.length > _maxRows) throw const FormatException('The file has more than $_maxRows rows. Split it into smaller files.');
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _mapping = CsvMapping.guess(rows.first) ??
            CsvMapping(
              dateColumn: 0,
              descriptionColumn: rows.first.length > 1 ? 1 : 0,
              amountColumn: rows.first.length > 2 ? 2 : 0,
            );
        _step = _Step.map;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not read the file: ${e is FormatException ? e.message : e}';
      });
    }
  }

  /// Steps shown while checking the file (the work, not a spinner).
  List<WorkStep> _progress = const [];

  void _showStep(int index, WorkStep step) {
    if (!mounted) return;
    setState(() {
      final list = [..._progress];
      if (index < list.length) {
        list[index] = step;
      } else {
        list.add(step);
      }
      _progress = list;
    });
  }

  Future<void> _buildPreview() async {
    final mapping = _mapping!;
    final service = ref.read(importServiceProvider);
    setState(() {
      _busy = true;
      _progress = const [];
    });
    try {
      final source = CsvImportSource(rows: _rows, mapping: mapping);
      _showStep(0, WorkStep('Reading ${_rows.length} rows…'));
      await Future<void>.delayed(Duration.zero); // let the step paint
      final raws = await source.fetchTransactions(card: widget.card);
      final skipped = source.rowErrors.length;
      _showStep(0, WorkStep('Read ${_rows.length} rows').finish());
      _showStep(1, WorkStep('Cleaning ${raws.length} transactions…'));
      await Future<void>.delayed(Duration.zero);
      final candidates = await service.prepare(raws);
      _showStep(
        1,
        WorkStep('Cleaned: ${raws.length} usable${skipped > 0 ? ', $skipped skipped (missing date or amount)' : ''}')
            .finish(),
      );
      final dupes = candidates.where((c) => c.isDuplicate).length;
      _showStep(2, WorkStep('Checked duplicates: ${dupes == 0 ? 'none found' : '$dupes found and unticked'}').finish());
      // A short beat so the finished steps can be read before moving on.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _invalidRows = skipped;
        _step = _Step.review;
        _busy = false;
      });
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) showSnack(context, 'Could not read rows: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.pick,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = _step == _Step.review ? _Step.map : _Step.pick);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('CSV import · ${widget.card.nickname}')),
        body: switch (_step) {
          _Step.pick => _buildPick(context),
          _Step.map => _buildMapping(context),
          _Step.review => ImportReview(
              candidates: _candidates,
              header: _invalidRows == 0
                  ? null
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        '$_invalidRows row${_invalidRows == 1 ? '' : 's'} couldn\'t be read and will be skipped. '
                        'Go back to adjust the column mapping.',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
              onSaved: () => Navigator.of(context).pop(),
            ),
        },
      ),
    );
  }

  Widget _buildPick(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.table_view_rounded, size: 56, color: scheme.primary),
        const SizedBox(height: 16),
        Text('Import a card statement', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Download your statement as a .csv file from your bank\'s website or app, then choose it here. '
          'It needs at least a date, a description and an amount column.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(_busy ? 'Reading…' : 'Choose CSV file'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 24),
        Text(
          'Tip: a sample file is included in the project at assets/sample/sample_statement.csv.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildMapping(BuildContext context) {
    final m = _mapping!;
    final header = m.hasHeader ? _rows.first : null;
    String colName(int i) {
      final h = header != null && i < header.length ? header[i].trim() : '';
      return h.isEmpty ? 'Column ${i + 1}' : 'Column ${i + 1}: $h';
    }

    final columns = List<int>.generate(_columnCount, (i) => i);
    final preview = CsvStatementReader.read(_rows.take(m.hasHeader ? 6 : 5).toList(), m, cardId: widget.card.id);

    Widget columnPicker(String label, int? value, ValueChanged<int?> onChanged, {bool optional = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<int?>(
          key: ValueKey('$label-$value-${m.hasHeader}'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (optional) const DropdownMenuItem<int?>(value: null, child: Text('None')),
            for (final c in columns) DropdownMenuItem<int?>(value: c, child: Text(colName(c), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text('${_fileName ?? 'File'} · ${_rows.length} rows', style: Theme.of(context).textTheme.titleSmall),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('First row is a header'),
                value: m.hasHeader,
                onChanged: (v) => setState(() => _mapping = m.copyWith(hasHeader: v)),
              ),
              const SizedBox(height: 8),
              columnPicker('Date column', m.dateColumn, (v) => setState(() => _mapping = m.copyWith(dateColumn: v ?? 0))),
              columnPicker('Description column', m.descriptionColumn,
                  (v) => setState(() => _mapping = m.copyWith(descriptionColumn: v ?? 0))),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('One amount column')),
                  ButtonSegment(value: true, label: Text('Debit + credit')),
                ],
                selected: {m.usesDebitCredit},
                onSelectionChanged: (s) => setState(() {
                  _mapping = s.first
                      ? m.copyWith(amountColumn: () => null, debitColumn: () => m.amountColumn ?? 0, creditColumn: () => null)
                      : m.copyWith(amountColumn: () => m.debitColumn ?? 0, debitColumn: () => null, creditColumn: () => null);
                }),
              ),
              const SizedBox(height: 12),
              if (!m.usesDebitCredit) ...[
                columnPicker('Amount column', m.amountColumn, (v) => setState(() => _mapping = m.copyWith(amountColumn: () => v ?? 0))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Purchases are positive numbers'),
                  subtitle: const Text('Turn off if your statement shows purchases as negative (e.g. -150.00).'),
                  value: m.chargesArePositive,
                  onChanged: (v) => setState(() => _mapping = m.copyWith(chargesArePositive: v)),
                ),
              ] else ...[
                columnPicker('Debit (money out)', m.debitColumn, (v) => setState(() => _mapping = m.copyWith(debitColumn: () => v)),
                    optional: true),
                columnPicker('Credit (money in)', m.creditColumn,
                    (v) => setState(() => _mapping = m.copyWith(creditColumn: () => v)),
                    optional: true),
              ],
              columnPicker('Reference / transaction ID (optional)', m.referenceColumn,
                  (v) => setState(() => _mapping = m.copyWith(referenceColumn: () => v)),
                  optional: true),
              DropdownButtonFormField<DateOrder>(
                initialValue: m.dateOrder,
                decoration: const InputDecoration(labelText: 'Date format'),
                items: [for (final o in DateOrder.values) DropdownMenuItem(value: o, child: Text(o.label))],
                onChanged: (v) => setState(() => _mapping = m.copyWith(dateOrder: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Comma is the decimal mark'),
                subtitle: const Text('For amounts written like 1.234,56'),
                value: m.decimalComma,
                onChanged: (v) => setState(() => _mapping = m.copyWith(decimalComma: v)),
              ),
              const SizedBox(height: 8),
              const SectionHeader('Preview'),
              Card(
                child: Column(
                  children: [
                    for (final r in preview)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          r.isValid ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: r.isValid ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          r.isValid ? r.transaction!.description : 'Row ${r.rowNumber}: ${r.error}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: r.isValid ? Text(DateFormat('MMM d, yyyy').format(r.transaction!.date)) : null,
                        trailing: r.isValid
                            ? AmountText(r.transaction!.amount, kind: r.transaction!.kind, colored: true)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy && _progress.isNotEmpty) ...[
                  WorkSteps(steps: _progress),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: _busy ? null : _buildPreview,
                  child: Text(_busy ? 'Checking…' : 'Review transactions'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
