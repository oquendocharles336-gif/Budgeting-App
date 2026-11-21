import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../data/models/debt.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';

class DebtFormScreen extends ConsumerStatefulWidget {
  const DebtFormScreen({super.key, this.existing});
  final Debt? existing;

  @override
  ConsumerState<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends ConsumerState<DebtFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _creditor;
  late final TextEditingController _total;
  late final TextEditingController _paid;
  late final TextEditingController _interest;
  late final TextEditingController _notes;
  DateTime? _due;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _creditor = TextEditingController(text: e?.creditor ?? '');
    _total = TextEditingController(text: e == null ? '' : Money.toInput(e.totalAmount));
    _paid = TextEditingController(text: e == null || e.initialPaid == 0 ? '' : Money.toInput(e.initialPaid));
    _interest = TextEditingController(
      text: e?.interestRateBp == null ? '' : (e!.interestRateBp! / 100).toStringAsFixed(2),
    );
    _notes = TextEditingController(text: e?.notes ?? '');
    _due = e?.dueDate;
  }

  @override
  void dispose() {
    for (final c in [_creditor, _total, _paid, _interest, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "3.5" -> 350 basis points.
  int? _interestBp() {
    final t = _interest.text.trim();
    if (t.isEmpty) return null;
    final v = Money.parse(t); // same 2-decimal parsing as money
    return v;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final e = widget.existing;
    final debt = Debt(
      id: e?.id,
      creditor: _creditor.text.trim(),
      totalAmount: Money.parse(_total.text)!,
      initialPaid: _paid.text.trim().isEmpty ? 0 : Money.parse(_paid.text)!,
      dueDate: _due,
      interestRateBp: _interestBp(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      isPaid: e?.isPaid ?? false,
      createdAt: e?.createdAt ?? DateTime.now(),
      paidAt: e?.paidAt,
    );
    try {
      await ref.read(debtServiceProvider).save(debt, currencySymbol: ref.read(currencyProvider).symbol);
      if (debt.dueDate != null) await ref.read(notificationServiceProvider).requestPermission();
      ref.refreshData();
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(currencyProvider).symbol;
    final moneyFormatter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add debt' : 'Edit debt')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _creditor,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Who do you owe?', hintText: 'e.g. Home Credit, Tito Ben', counterText: ''),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: moneyFormatter,
              decoration: InputDecoration(labelText: 'Total amount', prefixText: '$symbol '),
              validator: validateAmount,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: moneyFormatter,
              decoration: InputDecoration(
                labelText: 'Already paid (optional)',
                prefixText: '$symbol ',
                helperText: 'Payments made before you started tracking',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final err = validateAmount(v, allowZero: true);
                if (err != null) return err;
                final total = Money.parse(_total.text);
                if (total != null && Money.parse(v)! > total) return 'Can\'t be more than the total';
                return null;
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Due date (optional)'),
              subtitle: Text(_due == null ? 'No due date' : DateFormat('EEEE, MMMM d, yyyy').format(_due!)),
              trailing: _due == null
                  ? const Icon(Icons.edit_calendar_rounded)
                  : IconButton(
                      tooltip: 'Remove due date',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _due = null),
                    ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _due ?? now.add(const Duration(days: 30)),
                  firstDate: DateTime(now.year - 5),
                  lastDate: DateTime(now.year + 30),
                );
                if (picked != null) setState(() => _due = picked);
              },
            ),
            if (_due != null)
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 8),
                child: Text(
                  'You\'ll get a reminder the day before and on the due date at 9:00 AM.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _interest,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Interest rate (optional)', suffixText: '%'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final bp = Money.parse(v);
                if (bp == null || bp < 0) return 'Enter a number like 3.5';
                if (bp > 10000) return 'That seems too high (max 100%)';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save debt')),
          ],
        ),
      ),
    );
  }
}
