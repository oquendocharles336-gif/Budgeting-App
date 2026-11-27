import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../data/models/debt.dart';
import '../../../domain/debt/interest_calculator.dart';
import '../../../domain/debt/monthly_due.dart';
import '../../../domain/services/app_lock_service.dart';
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
  late final TextEditingController _lenderDetail;
  late final TextEditingController _term;
  /// Day of the month the payment is due (1-31), every month. Null = none.
  int? _dueDay;
  late DebtType _type;
  LenderType? _lenderType;
  late InterestType _interestType;
  late InterestPeriod _interestPeriod;
  bool _saving = false;

  /// Asked when adding: true = new debt (also added to expenses),
  /// false = existing debt (reminder only). Null until the user picks.
  bool? _isNew;
  bool _originMissing = false;

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
    _dueDay = e?.dueDay;
    _type = e?.type ?? DebtType.loan;
    _lenderType = e?.lenderType;
    _lenderDetail = TextEditingController(text: e?.lenderDetail ?? '');
    _interestType = e?.interestType ?? InterestType.simple;
    _interestPeriod = e?.interestPeriod ?? InterestPeriod.month;
    _term = TextEditingController(text: e?.termMonths?.toString() ?? '');
    // Keep the monthly estimate up to date while typing.
    for (final c in [_total, _paid, _interest, _term]) {
      c.addListener(() => setState(() {}));
    }
  }

  /// The loan term: a positive whole number of months, or null.
  int? _termMonths() {
    final n = int.tryParse(_term.text.trim());
    return (n == null || n <= 0) ? null : n;
  }

  /// Required, whole months only (digits only, so no decimals), 1-600.
  static String? validateTerm(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter how many months (Gaano katagal babayaran)';
    if (!RegExp(r'^\d+$').hasMatch(t)) return 'Whole months only, e.g. 12';
    final n = int.tryParse(t);
    if (n == null || n <= 0) return 'Must be at least 1 month';
    if (n > 600) return 'Enter 1 to 600 months';
    return null;
  }

  @override
  void dispose() {
    for (final c in [_creditor, _total, _paid, _interest, _notes, _lenderDetail, _term]) {
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
    final e = widget.existing;
    final formOk = _form.currentState!.validate();
    setState(() => _originMissing = e == null && _isNew == null);
    if (!formOk || _originMissing) return;
    setState(() => _saving = true);
    final debt = Debt(
      id: e?.id,
      creditor: _creditor.text.trim(),
      type: _type,
      lenderType: _lenderType,
      lenderDetail: _lenderType == LenderType.other && _lenderDetail.text.trim().isNotEmpty ? _lenderDetail.text.trim() : null,
      interestType: _interestType,
      interestPeriod: _interestPeriod,
      termMonths: _termMonths(),
      totalAmount: Money.parse(_total.text)!,
      initialPaid: _paid.text.trim().isEmpty ? 0 : Money.parse(_paid.text)!,
      dueDay: _dueDay,
      // A due day added to an older debt counts from today, so it doesn't
      // show months of missed payments.
      dueFrom: e == null
          ? null
          : (e.dueDay == null && _dueDay != null ? DateTime.now() : e.dueFrom),
      interestRateBp: _interestBp(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      isPaid: e?.isPaid ?? false,
      isNew: e?.isNew ?? _isNew!,
      createdAt: e?.createdAt ?? DateTime.now(),
      paidAt: e?.paidAt,
    );
    try {
      await ref.read(debtServiceProvider).save(debt, currencySymbol: ref.read(currencyProvider).symbol);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Could not save debt: $err', error: true);
      return;
    }
    // Saved: refresh the list first so the Debts screen updates even if the
    // (optional) notification permission prompt below fails.
    ref.refreshData();
    if (debt.dueDay != null) await _askForReminders();
    if (mounted) Navigator.of(context).pop();
  }

  /// The first time a debt gets a deadline: say what the reminder is for,
  /// then ask the OS for notification permission.
  Future<void> _askForReminders() async {
    const key = 'debt_reminders_explained';
    final settings = ref.read(settingsRepositoryProvider);
    try {
      if (await settings.get(key) != null) return;
      if (!mounted) return;
      final yes = await confirm(
        context,
        title: 'Remind you before it\'s due?',
        message: 'Pitaka can notify you 2 days before each monthly payment day. '
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
            if (widget.existing == null) ...[
              Text('Is this a new debt?', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('New'), icon: Icon(Icons.fiber_new_rounded)),
                  ButtonSegment(value: false, label: Text('Existing'), icon: Icon(Icons.history_rounded)),
                ],
                selected: {?_isNew},
                onSelectionChanged: (s) => setState(() {
                  _isNew = s.isEmpty ? null : s.first;
                  _originMissing = false;
                }),
              ),
              const SizedBox(height: 6),
              Text(
                switch (_isNew) {
                  true => 'Money you just borrowed or spent on credit. It\'s also added to your expenses '
                      '(category "Debt"), so it counts in this month\'s budget.',
                  false => 'A debt you already had. Only a reminder: it\'s added to your debts, '
                      'not to expenses or the budget.',
                  null => 'New: just borrowed or bought on credit (added to expenses). '
                      'Existing: you already owed it (reminder only).',
                },
                style: TextStyle(
                  color: _originMissing ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              if (_originMissing)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Choose New or Existing',
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 20),
            ] else if (widget.existing!.isNew) ...[
              Text(
                'New debt: its expense in "Debt" is updated when you save.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _creditor,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Who do you owe?', hintText: 'e.g. Home Credit, Tito Ben', counterText: ''),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            Text('Where did you borrow?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in LenderType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _lenderType == t,
                    onSelected: (on) => setState(() => _lenderType = on ? t : null),
                  ),
              ],
            ),
            if (_lenderType == LenderType.other) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _lenderDetail,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Type where you borrowed', hintText: 'e.g. Paluwagan, online seller', counterText: ''),
              ),
            ],
            const SizedBox(height: 16),
            Text('Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in DebtType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: moneyFormatter,
              decoration: InputDecoration(labelText: 'Amount borrowed', prefixText: '$symbol '),
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
            const SizedBox(height: 20),
            // Loan term: required, whole months.
            TextFormField(
              controller: _term,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: const InputDecoration(
                labelText: 'Loan term (months) *',
                hintText: 'e.g. 12',
                helperText: 'Gaano katagal babayaran (in months)',
                prefixIcon: Icon(Icons.date_range_rounded),
                suffixText: 'months',
              ),
              validator: validateTerm,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _dueDay,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: InputDecoration(
                labelText: 'Payment day every month',
                prefixIcon: const Icon(Icons.event_repeat_rounded),
                helperText: _dueDay == null
                    ? 'Which day of the month you pay (optional)'
                    : '${MonthlyDue.everyLabel(_dueDay!)} until it\'s paid off',
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('No payment day')),
                for (var d = 1; d <= 31; d++)
                  DropdownMenuItem<int?>(value: d, child: Text(MonthlyDue.everyLabel(d))),
              ],
              onChanged: (v) => setState(() => _dueDay = v),
            ),
            if (_dueDay != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6, bottom: 8),
                child: Text(
                  'You\'ll get a reminder 2 days before at 9:00 AM, every month, until the debt is settled.'
                  '${_dueDay! > 28 ? ' In shorter months it\'s the last day of the month.' : ''}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            const SizedBox(height: 16),
            const SizedBox(height: 8),
            Text('Interest (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _interest,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Rate', suffixText: '%'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final bp = Money.parse(v);
                      if (bp == null || bp < 0) return 'Enter a number like 3.5';
                      if (bp > 10000) return 'Max 100%';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<InterestPeriod>(
                    initialValue: _interestPeriod,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Charged'),
                    items: [for (final p in InterestPeriod.values) DropdownMenuItem(value: p, child: Text(p.label))],
                    onChanged: (v) => setState(() => _interestPeriod = v ?? _interestPeriod),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<InterestType>(
              showSelectedIcon: false,
              segments: [for (final t in InterestType.values) ButtonSegment(value: t, label: Text(t.label))],
              selected: {_interestType},
              onSelectionChanged: (v) => setState(() => _interestType = v.first),
            ),
            const SizedBox(height: 6),
            Text(
              _interestType == InterestType.simple
                  ? 'Simple: interest is always on the amount you borrowed (common for lending apps and add-on loans).'
                  : 'Compound: interest is on what you still owe, so it goes down as you pay (common for bank loans).',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            _MonthlyEstimate(
              quote: () {
                final total = Money.parse(_total.text) ?? 0;
                final paid = _paid.text.trim().isEmpty ? 0 : (Money.parse(_paid.text) ?? 0);
                return InterestCalculator.quote(
                  principal: total,
                  remaining: total - paid,
                  rateBp: _interestBp(),
                  type: _interestType,
                  period: _interestPeriod,
                  termMonths: _termMonths(),
                );
              }(),
              symbol: symbol,
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

/// Live "what to prepare each month" preview in the form.
class _MonthlyEstimate extends StatelessWidget {
  const _MonthlyEstimate({required this.quote, required this.symbol});
  final InterestQuote? quote;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    if (q == null || q.dueThisMonth <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    String m(int c) => Money.format(c, symbol: symbol);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onSecondaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prepare about ${m(q.dueThisMonth)} a month', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Interest: ${m(q.interestThisMonth)} a month'),
            if (q.totalInterest != null) Text('Total interest over the term: ${m(q.totalInterest!)}'),
            if (q.monthlyPayment == null) const Text('Add the loan term to include the principal.'),
          ],
        ),
      ),
    );
  }
}
