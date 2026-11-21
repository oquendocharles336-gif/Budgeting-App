import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/op_key.dart';
import '../../../data/models/category.dart';
import '../../../data/models/pay_later.dart';
import '../../../domain/services/app_lock_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/pending_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/optimistic.dart';

class PayLaterFormScreen extends ConsumerStatefulWidget {
  const PayLaterFormScreen({super.key, this.existing});
  final PayLaterItem? existing;

  @override
  ConsumerState<PayLaterFormScreen> createState() => _PayLaterFormScreenState();
}

class _PayLaterFormScreenState extends ConsumerState<PayLaterFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _item;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  int? _categoryId;
  late DateTime _purchaseDate;
  late DateTime _dueDate;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  bool get _isPaid => widget.existing?.isPaid ?? false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    _item = TextEditingController(text: e?.item ?? '');
    _amount = TextEditingController(text: e == null ? '' : Money.toInput(e.amount));
    _notes = TextEditingController(text: e?.notes ?? '');
    _categoryId = e?.categoryId;
    _purchaseDate = e?.purchaseDate ?? Dates.startOfDay(now);
    _dueDate = e?.dueDate ?? DateTime(now.year, now.month + 1, now.day);
  }

  @override
  void dispose() {
    _item.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool due}) async {
    final initial = due ? _dueDate : _purchaseDate;
    final picked = await showDatePicker(
      context: context,
      helpText: due ? 'Due date' : 'Purchase date',
      initialDate: initial,
      // A due date can't be before the purchase.
      firstDate: due ? _purchaseDate : DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3660)),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _purchaseDate = picked;
        if (_dueDate.isBefore(picked)) _dueDate = picked;
      }
    });
  }

  /// The operation key for this form's save, kept for "Try again".
  final _opKey = newOpKey('pay_later');

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final e = widget.existing;
    final item = PayLaterItem(
      id: e?.id,
      item: _item.text.trim(),
      amount: _isPaid ? e!.amount : Money.parse(_amount.text)!.abs(),
      categoryId: _isPaid ? e!.categoryId : _categoryId,
      purchaseDate: _purchaseDate,
      dueDate: _dueDate,
      status: e?.status ?? PayLaterStatus.unpaid,
      paidAt: e?.paidAt,
      expenseTxId: e?.expenseTxId,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: e?.createdAt ?? now,
      updatedAt: now,
    );
    // Asked once, before the screen closes (it needs this screen).
    if (!_isPaid) await _askForReminders();
    if (!mounted) return;
    final service = ref.read(payLaterServiceProvider);
    final symbol = ref.read(currencyProvider).symbol;
    final key = _opKey;
    final preview = e == null ? item.copyWith(id: tempId()) : item;
    // Optimistic: the list shows it and "Saved" appears at once.
    OptimisticWrite.run(
      context,
      savedText: _isEdit ? 'Changes saved' : 'Saved',
      what: '"${item.item}"',
      show: (c) {
        final pending = c.read(pendingPayLaterProvider.notifier)..put(key, preview);
        return () => pending.clear(key);
      },
      write: () => service.save(item, currencySymbol: symbol, opKey: key),
    );
    Navigator.of(context).pop();
  }

  /// The first time: say what the reminder is for, then ask the OS.
  Future<void> _askForReminders() async {
    const key = 'pay_later_reminders_explained';
    final settings = ref.read(settingsRepositoryProvider);
    try {
      if (await settings.get(key) != null) return;
      if (!mounted) return;
      final yes = await confirm(
        context,
        title: 'Remind you before it\'s due?',
        message: 'Pitaka can notify you 2 days before the due date, at 9:00 AM. '
            'Reminders are set on this phone; nothing is sent online.',
        confirmLabel: 'Turn on',
        destructive: false,
      );
      await settings.set(key, yes ? 'yes' : 'no');
      if (yes) await LockGuard.run(() => ref.read(notificationServiceProvider).requestPermission());
    } catch (err) {
      debugPrint('Notification permission request failed: $err');
    }
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    var removeExpense = false;
    if (e.isPaid && e.expenseTxId != null) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this item?'),
          content: const Text('It was paid, so it has an expense in Activity. Keep that expense or remove it too?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep expense')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove both'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      removeExpense = choice;
    } else {
      final ok = await confirm(context, title: 'Delete this item?', message: 'Its reminder is cancelled. This can\'t be undone.');
      if (!ok) return;
    }
    try {
      await ref.read(payLaterServiceProvider).delete(e.id!, removeExpense: removeExpense);
    } catch (err) {
      if (mounted) showSnack(context, 'Could not delete: $err', error: true);
      return;
    }
    ref.refreshData();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final symbol = ref.watch(currencyProvider).symbol;
    final categories = (ref.watch(categoriesProvider).asDataOrNull ?? const <Category>[]).where((c) => !c.isIncome).toList();
    final fmt = DateFormat('EEE, MMM d, yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Pay Later' : 'Add Pay Later'),
        actions: [
          if (_isEdit) IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: Form(
        key: _form,
        child: FocusTraversalGroup(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              if (_isPaid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Already paid. Amount and category are locked because its expense is saved. '
                    'Mark it unpaid first to change them.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              TextFormField(
                controller: _item,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Item or name', hintText: 'e.g. Rice cooker', counterText: ''),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter what you bought' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                enabled: !_isPaid,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 'Amount', prefixText: '$symbol '),
                validator: _isPaid ? null : validateAmount,
              ),
              const SizedBox(height: 20),
              Text('Category', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      avatar: CategoryAvatar(category: c, size: 24),
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: _isPaid ? null : (_) => setState(() => _categoryId = c.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shopping_bag_outlined),
                title: const Text('Purchase date'),
                subtitle: Text(fmt.format(_purchaseDate)),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: () => _pickDate(due: false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: const Text('Due date'),
                subtitle: Text(fmt.format(_dueDate)),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: () => _pickDate(due: true),
              ),
              Text(
                'Reminder: 2 days before the due date, at 9:00 AM.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                minLines: 1,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. SPayLater, 0% for 3 months'),
              ),
              const SizedBox(height: 8),
              Text(
                'Not counted as spending until you mark it paid. Then it\'s added once as an expense.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_isEdit ? 'Save changes' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
