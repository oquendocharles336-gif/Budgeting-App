import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/op_key.dart';
import '../../../data/models/business.dart';
import '../../../data/models/transaction_entry.dart';
import '../../../domain/business/capital_math.dart';
import '../../../domain/transfer/transfer_fee.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/business_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/pending_providers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/optimistic.dart';
import '../../widgets/status_badge.dart';

/// Business capital: the ledger (deposits, withdrawals, fees, sales added)
/// and its balance, which is always the sum of the ledger.
class CapitalScreen extends ConsumerWidget {
  const CapitalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(capitalEntriesProvider);
    final balance = ref.watch(capitalBalanceProvider).asDataOrNull ?? 0;
    final t = context.tokens;
    void open(bool withdraw) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CapitalMoveScreen(withdraw: withdraw)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        HeroCard(
          label: 'Capital balance',
          value: entries.hasValue ? AmountText(balance) : const SkeletonBox(width: 160, height: 36),
          caption: 'Money you moved in from your personal budget, minus what you took out.',
          footer: Row(
            children: [
              Expanded(
                // On the hero gradient: a white pill with accent text.
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.white,
                    foregroundColor: Contrast.ensure(t.heroEnd, Colors.white),
                  ),
                  onPressed: () => open(false),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add to capital'),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.white.withValues(alpha: 0),
                    foregroundColor: t.onHero,
                    disabledForegroundColor: t.onHero.withValues(alpha: 0.6),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
                    shape: const StadiumBorder(),
                  ),
                  // Nothing to take out: disabled (with the reason for screen readers).
                  onPressed: balance > 0 ? () => open(true) : null,
                  icon: const Icon(Icons.remove_rounded),
                  label: Text('Withdraw', semanticsLabel: balance > 0 ? 'Withdraw from capital' : 'Withdraw, no capital to withdraw'),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('History'),
        AsyncView<List<CapitalEntry>>(
          value: entries,
          onRetry: () => ref.invalidate(capitalEntriesProvider),
          loading: const SkeletonList(rows: 4, padding: EdgeInsets.zero),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.savings_rounded,
                title: 'No capital yet',
                message: 'Tap "Add to capital" to move money from a personal account into the business.',
              );
            }
            return Card(
              child: Column(
                children: [for (final (i, e) in list.indexed) CascadeIn(index: i, child: _EntryTile(entry: e))],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});
  final CapitalEntry entry;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message: entry.kind == CapitalKind.withdrawal
          ? 'The transfer is deleted too: the money leaves the personal account and goes back to capital, with any fee.'
          : 'The transfer that moved this money is deleted too, so the money (and any fee) goes back to the personal account.',
    );
    if (!ok) return;
    try {
      await ref.read(businessServiceProvider).deleteCapitalEntry(entry);
      ref.refreshData();
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not delete: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final saving = isUnsaved(entry.id);
    final (IconData icon, String title) = switch (entry.kind) {
      CapitalKind.withdrawal => (Icons.north_east_rounded, 'Taken out to personal'),
      CapitalKind.fee => (Icons.percent_rounded, 'Withdrawal fee'),
      CapitalKind.salesAdded => (Icons.savings_rounded, 'Sales added to budget'),
      _ => (Icons.south_west_rounded, 'Moved in from personal'),
    };
    final deletable = !saving && (entry.kind == CapitalKind.deposit || entry.kind == CapitalKind.withdrawal);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: ExcludeSemantics(child: Icon(icon, color: scheme.onSecondaryContainer)),
      ),
      title: Text(entry.note ?? title),
      subtitle: Text(
        [
          if (entry.note != null) title,
          DateFormat('MMM d, yyyy').format(entry.date),
          if (entry.kind == CapitalKind.salesAdded && entry.memoAmount != null)
            '${formatMoney(ref, entry.memoAmount!)} to personal, capital unchanged',
        ].join(' · '),
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (saving) const StatusBadge(label: 'Saving…', icon: Icons.sync_rounded),
          if (entry.amount != 0)
            AmountText(entry.amount.abs(), kind: entry.amount > 0 ? TransactionKind.income : TransactionKind.expense, colored: true),
          if (deletable)
            IconButton(
              tooltip: 'Delete entry',
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }
}

/// Moves money into capital ([withdraw] false) or back out to a personal
/// account. Both are transfers with an optional fee that is always shown
/// before confirming. A withdrawal can't be more than the capital balance.
class CapitalMoveScreen extends ConsumerStatefulWidget {
  const CapitalMoveScreen({super.key, required this.withdraw});
  final bool withdraw;

  @override
  ConsumerState<CapitalMoveScreen> createState() => _CapitalMoveScreenState();
}

class _CapitalMoveScreenState extends ConsumerState<CapitalMoveScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _fee = TextEditingController();
  final _note = TextEditingController();
  int? _account;
  DateTime _date = DateTime.now();
  bool _saving = false;

  /// One key per move: a double tap or "Try again" can't move money twice.
  late final _opKey = newOpKey(widget.withdraw ? 'capital_out' : 'capital_in');

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _amountValue => Money.parse(_amount.text)?.abs() ?? 0;
  int get _feeValue => _fee.text.trim().isEmpty ? 0 : (Money.parse(_fee.text)?.abs() ?? 0);

  String _accountName(int? id) =>
      id == null ? 'Cash' : ((ref.read(cardMapProvider).asDataOrNull ?? const {})[id]?.nickname ?? 'Account');

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final symbol = ref.read(currencyProvider).symbol;
    String m(int v) => Money.format(v, symbol: symbol);
    final amount = _amountValue;
    final fee = _feeValue;
    final String message;
    var short = false;
    if (widget.withdraw) {
      final plan = WithdrawPlan(amount: amount, fee: fee);
      message = 'Business capital: -${m(plan.capitalDebit)}'
          '${plan.hasFee ? ' (amount ${m(amount)} + fee ${m(fee)})' : ''}\n'
          '${_accountName(_account)}: +${m(plan.personalCredit)}'
          '${plan.hasFee ? '\n\nThe fee is taken from capital and listed in its history.' : ''}';
    } else {
      final plan = TransferFee.plan(amount: amount, fee: fee);
      final available = await ref.read(transactionServiceProvider).availableBefore(
            kind: TransactionKind.transfer,
            accountId: _account,
          );
      if (!mounted) return;
      short = available != null && plan.sourceDebit > available;
      message = '${_accountName(_account)}: -${m(plan.sourceDebit)}'
          '${plan.hasFee ? ' (amount ${m(amount)} + fee ${m(fee)})' : ''}\n'
          'Business capital: +${m(plan.destinationCredit)}'
          '${plan.hasFee ? '\n\nThe fee is saved as an expense in "Fees".' : ''}'
          '${short ? '\n\n${_accountName(_account)} has ${m(available)}; its balance will go below zero.' : ''}';
    }
    // Always shown: what leaves, what arrives, and the fee, before saving.
    final ok = await confirm(
      context,
      title: short ? 'Insufficient balance' : (widget.withdraw ? 'Withdraw from capital?' : 'Move to business capital?'),
      message: message,
      confirmLabel: short ? 'Move anyway' : (widget.withdraw ? 'Withdraw' : 'Move'),
      destructive: false,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);

    final service = ref.read(businessServiceProvider);
    final key = _opKey;
    final account = _account;
    final date = _date;
    final note = _note.text;
    final now = DateTime.now();
    final previews = widget.withdraw
        ? CapitalMath.withdrawEntries(WithdrawPlan(amount: amount, fee: fee), date: date, now: now, note: note.trim().isEmpty ? null : note.trim())
        : [CapitalEntry(amount: amount, note: note.trim().isEmpty ? null : note.trim(), date: date, createdAt: now)];
    OptimisticWrite.run(
      context,
      savedText: widget.withdraw ? 'Withdrew ${m(amount)} from capital' : 'Moved ${m(amount)} to capital',
      what: widget.withdraw ? 'the withdrawal' : 'the capital deposit',
      show: (c) {
        final pending = c.read(pendingCapitalProvider.notifier);
        for (final (i, e) in previews.indexed) {
          pending.put('$key#$i', CapitalEntry(
            id: tempId(),
            amount: e.amount,
            kind: e.kind,
            note: e.note,
            date: e.date,
            createdAt: e.createdAt,
          ));
        }
        return () {
          for (var i = 0; i < previews.length; i++) {
            pending.clear('$key#$i');
          }
        };
      },
      write: () => widget.withdraw
          ? service.withdrawFromCapital(amount: amount, fee: fee, toAccountId: account, date: date, note: note, opKey: key)
          : service.moveToCapital(amount: amount, fee: fee, fromAccountId: account, date: date, note: note, opKey: key),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(currencyProvider).symbol;
    final scheme = Theme.of(context).colorScheme;
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final balance = ref.watch(capitalBalanceProvider).asDataOrNull ?? 0;
    final fee = _feeValue;
    final w = widget.withdraw;
    return Scaffold(
      appBar: AppBar(title: Text(w ? 'Withdraw from capital' : 'Add to capital')),
      body: Form(
        key: _form,
        child: FocusTraversalGroup(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              if (w)
                Semantics(
                  container: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Capital balance: ${Money.format(balance, symbol: symbol)}', style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
              TextFormField(
                controller: _amount,
                autofocus: true,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: money,
                decoration: InputDecoration(labelText: 'Amount', prefixText: '$symbol '),
                validator: (v) {
                  final basic = validateAmount(v);
                  if (basic != null || !w) return basic;
                  // The limit is shown here, before anything is saved.
                  return CapitalMath.withdrawError(balance: balance, amount: _amountValue, fee: _feeValue);
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AccountDropdown(
                value: _account,
                label: w ? 'To (personal account)' : 'From (personal account)',
                onChanged: (v) => setState(() => _account = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fee,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: money,
                decoration: InputDecoration(
                  labelText: 'Fee (optional)',
                  prefixText: '$symbol ',
                  helperText: w ? 'Taken from capital, listed in its history.' : 'Saved as a separate expense in "Fees".',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? null : validateAmount(v, allowZero: true),
                onChanged: (_) => setState(() {}),
              ),
              if (_amountValue > 0) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    w
                        ? 'Capital goes down by ${Money.format(_amountValue + fee, symbol: symbol)} · '
                            '${_accountName(_account)} gets ${Money.format(_amountValue, symbol: symbol)}'
                        : '${_accountName(_account)} goes down by ${Money.format(_amountValue + fee, symbol: symbol)} · '
                            'capital gets ${Money.format(_amountValue, symbol: symbol)}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: const Text('Date'),
                subtitle: Text(DateFormat('EEE, MMM d, yyyy').format(_date)),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
                },
              ),
              TextFormField(
                controller: _note,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: w ? 'e.g. Owner\'s pay' : 'e.g. Starting capital',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving || (w && balance <= 0) ? null : _save,
                child: Text(w ? 'Withdraw' : 'Move to capital'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
