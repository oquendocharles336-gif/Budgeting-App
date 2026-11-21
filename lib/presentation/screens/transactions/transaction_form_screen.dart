import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../data/models/category.dart';
import '../../../data/models/payment_card.dart';
import '../../../data/models/raw_transaction.dart';
import '../../../data/models/transaction_entry.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../cards/card_form_screen.dart';

/// Add a new transaction, or edit/delete an existing one.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.existing, this.initialCardId});

  final TransactionEntry? existing;
  final int? initialCardId;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late TransactionKind _kind;
  late DateTime _date;
  int? _categoryId;
  int? _cardId;
  bool _categoryTouched = false;
  bool _saving = false;
  Timer? _suggestTimer;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : Money.toInput(e.amount));
    _description = TextEditingController(text: e?.description ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _kind = e?.kind ?? TransactionKind.expense;
    _date = e?.date ?? DateTime.now();
    _categoryId = e?.categoryId;
    _cardId = e?.cardId ?? widget.initialCardId;
    _categoryTouched = e != null;
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onDescriptionChanged(String text) {
    if (_categoryTouched) return;
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 350), () async {
      final id = await ref.read(transactionServiceProvider).suggestCategory(text);
      if (!mounted || _categoryTouched || id == null) return;
      setState(() => _categoryId = id);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    // No category picked: the keyword rules decide, falling back to "Other".
    setState(() => _saving = true);
    final amount = Money.parse(_amount.text)!.abs();
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final service = ref.read(transactionServiceProvider);
    try {
      if (_isEdit) {
        await service.update(widget.existing!.copyWith(
          amount: amount,
          kind: _kind,
          description: _description.text.trim(),
          categoryId: () => _categoryId,
          cardId: () => _cardId,
          date: _date,
          notes: () => notes,
        ));
      } else {
        await service.create(RawTransaction(
          date: _date,
          description: _description.text.trim(),
          amount: amount,
          kind: _kind,
          source: TransactionSourceType.manual,
          cardId: _cardId,
          categoryId: _categoryId,
          notes: notes,
        ));
      }
      ref.refreshData();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not save: $e', error: true);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Delete transaction?', message: 'This can\'t be undone.');
    if (!ok) return;
    await ref.read(transactionServiceProvider).delete(widget.existing!.id!);
    ref.refreshData();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final symbol = ref.watch(currencyProvider).symbol;
    final categories = ref.watch(categoriesProvider);
    final cards = ref.watch(cardsProvider).asDataOrNull ?? const <PaymentCard>[];
    final existing = widget.existing;

    // Keep an archived card selectable when editing an old transaction.
    final allCards = ref.watch(cardMapProvider).asDataOrNull ?? const <int, PaymentCard>{};
    final archivedCard = (_cardId != null && !cards.any((c) => c.id == _cardId)) ? allCards[_cardId] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'New transaction'),
        actions: [
          if (_isEdit) IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SegmentedButton<TransactionKind>(
              segments: const [
                ButtonSegment(value: TransactionKind.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward_rounded)),
                ButtonSegment(value: TransactionKind.income, label: Text('Income / refund'), icon: Icon(Icons.arrow_downward_rounded)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amount,
              autofocus: !_isEdit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: Theme.of(context).textTheme.headlineMedium,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$symbol ',
                prefixStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              validator: validateAmount,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'What was it for?', hintText: 'e.g. Jollibee lunch', counterText: ''),
              onChanged: _onDescriptionChanged,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
            ),
            const SizedBox(height: 20),
            Text('Category', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            AsyncView<List<Category>>(
              value: categories,
              data: (list) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in list)
                    ChoiceChip(
                      avatar: CategoryAvatar(category: c, size: 24),
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() {
                        _categoryId = c.id;
                        _categoryTouched = true;
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int?>(
              initialValue: _cardId,
              decoration: const InputDecoration(labelText: 'Paid with'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Row(children: [Icon(Icons.payments_rounded), SizedBox(width: 10), Text('Cash')]),
                ),
                for (final c in [...cards, ?archivedCard])
                  DropdownMenuItem<int?>(
                    value: c.id,
                    child: Row(
                      children: [
                        Icon(Icons.credit_card_rounded, color: Color(c.color)),
                        const SizedBox(width: 10),
                        Flexible(child: Text(c.label, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _cardId = v),
            ),
            if (cards.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CardFormScreen())),
                  icon: const Icon(Icons.add_card_rounded),
                  label: const Text('Add a card'),
                ),
              ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Date'),
              subtitle: Text(DateFormat('EEEE, MMMM d, yyyy').format(_date)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (existing != null && existing.source != TransactionSourceType.manual) ...[
              const SizedBox(height: 8),
              Text(
                'Imported from ${existing.source.label}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_isEdit ? 'Save changes' : 'Add transaction'),
            ),
          ],
        ),
      ),
    );
  }
}
