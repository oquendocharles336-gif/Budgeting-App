import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/op_key.dart';
import '../../../data/models/category.dart';
import '../../../data/models/debt.dart';
import '../../../data/models/payment_card.dart';
import '../../../data/models/raw_transaction.dart';
import '../../../data/models/transaction_entry.dart';
import '../../../domain/services/transaction_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/optimistic_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/animated_icons.dart';
import '../../widgets/optimistic.dart';
import '../cards/card_form_screen.dart';
import '../debts/debt_form_screen.dart';

/// Add a new transaction, or edit/delete an existing one.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.existing, this.initialCardId, this.draft});

  final TransactionEntry? existing;
  final int? initialCardId;

  /// Values to start a new transaction with (e.g. "Try again" after a
  /// save failed). Ignored when editing.
  final TransactionEntry? draft;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late final TextEditingController _customCategory;

  /// Optional transfer fee (new transfers only).
  final _fee = TextEditingController();

  /// Fee already saved with the transfer being edited.
  Future<int>? _existingFee;
  late TransactionKind _kind;
  late DateTime _date;
  int? _categoryId;
  int? _cardId;
  int? _toCardId;
  bool _categoryTouched = false;
  bool _saving = false;

  /// Income from "Borrowed money": where it was borrowed (for the new debt).
  LenderType? _loanLender;

  /// Last categories shown, so _save can look up the picked one.
  List<Category> _categoryList = const [];

  Category? get _selectedCategory {
    for (final c in _categoryList) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }
  Timer? _suggestTimer;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? widget.draft;
    _amount = TextEditingController(text: e == null ? '' : Money.toInput(e.amount));
    _description = TextEditingController(text: e?.description ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _customCategory = TextEditingController(text: e?.customCategory ?? '');
    _kind = e?.kind ?? TransactionKind.expense;
    _date = e?.date ?? DateTime.now();
    _categoryId = e?.categoryId;
    _cardId = e?.cardId ?? widget.initialCardId;
    _toCardId = e?.toCardId;
    _categoryTouched = e != null;
    final existing = widget.existing;
    if (existing != null && existing.isTransfer && existing.id != null) {
      _existingFee = ref.read(transactionServiceProvider).feeOf(existing.id!);
    }
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    _customCategory.dispose();
    _fee.dispose();
    super.dispose();
  }

  void _onDescriptionChanged(String text) {
    // Keyword rules point at expense categories only.
    if (_categoryTouched || _kind != TransactionKind.expense) return;
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

  /// Warns when an expense or transfer is more than the paying account
  /// holds. Returns false if the user backs out.
  Future<bool> _confirmBalance(int amount) async {
    final int? available;
    try {
      available = await ref.read(transactionServiceProvider).availableBefore(
            kind: _kind,
            accountId: _cardId,
            editing: widget.existing,
          );
    } catch (e) {
      debugPrint('Balance check failed: $e');
      return true; // Never block saving because the check itself failed.
    }
    if (available == null || amount <= available) return true;
    if (!mounted) return true;
    final account = _cardId == null ? null : (ref.read(cardMapProvider).asDataOrNull ?? const {})[_cardId];
    final name = account?.nickname ?? 'Cash';
    final what = (account?.isCredit ?? false) ? 'available credit' : 'balance';
    final symbol = ref.read(currencyProvider).symbol;
    final kind = _kind == TransactionKind.transfer ? 'transfer' : 'expense';
    return confirm(
      context,
      title: 'Insufficient balance',
      message: '$name has ${Money.format(available, symbol: symbol)} $what, but this $kind is '
          '${Money.format(amount, symbol: symbol)}.\n\n'
          'Save anyway? The $what will go below zero. You can correct it later in Wallets.',
      confirmLabel: 'Save anyway',
      destructive: false,
    );
  }

  /// The optional fee typed for a new transfer (0 when empty).
  int get _feeValue {
    if (_kind != TransactionKind.transfer || _isEdit) return 0;
    final text = _fee.text.trim();
    if (text.isEmpty) return 0;
    return (Money.parse(text) ?? 0).abs();
  }

  String _accountName(int? id) {
    if (id == null) return 'Cash';
    return (ref.read(cardMapProvider).asDataOrNull ?? const {})[id]?.nickname ?? 'Account';
  }

  /// The fee is always spelled out before a transfer with a fee is saved.
  Future<bool> _confirmFee(int amount, int fee) {
    final symbol = ref.read(currencyProvider).symbol;
    String m(int v) => Money.format(v, symbol: symbol);
    return confirm(
      context,
      title: 'Transfer with a fee',
      message: '${_accountName(_cardId)}: -${m(amount + fee)} (amount ${m(amount)} + fee ${m(fee)})\n'
          '${_accountName(_toCardId)}: +${m(amount)}\n\n'
          'The fee of ${m(fee)} is saved as a separate expense in "Fees".',
      confirmLabel: 'Transfer',
      destructive: false,
    );
  }

  /// One key per transfer on this form: a double tap or "Try again" can't
  /// save the transfer (or its fee) twice.
  final _transferKey = newOpKey('transfer');

  /// Transfer + fee, optimistic: both rows show at once with "Saved", then
  /// are written together in one SQLite transaction. On failure they're
  /// taken back out and "Try again" repeats the same write.
  void _saveTransferWithFee({
    required int amount,
    required int fee,
    required String description,
    required String? notes,
  }) {
    final service = ref.read(transactionServiceProvider);
    final from = _cardId;
    final to = _toCardId;
    final date = _date;
    final key = _transferKey;
    final now = DateTime.now();
    TransactionEntry row(TransactionKind kind, int value, String text, {int? toCard}) => TransactionEntry(
          amount: value,
          kind: kind,
          description: text,
          cardId: from,
          toCardId: toCard,
          date: date,
          notes: notes,
          source: TransactionSourceType.manual,
          affectsBalance: true,
          createdAt: now,
          updatedAt: now,
        );
    OptimisticWrite.run(
      context,
      savedText: 'Saved transfer and fee',
      what: 'the transfer',
      show: (c) {
        final pending = c.read(pendingTransactionsProvider.notifier);
        final ids = [
          pending.add(row(TransactionKind.transfer, amount, description, toCard: to)),
          pending.add(row(TransactionKind.expense, fee, 'Transfer fee')),
        ];
        return () {
          for (final id in ids) {
            pending.clear(id);
          }
        };
      },
      write: () => service.createTransfer(
        amount: amount,
        fee: fee,
        fromAccountId: from,
        toAccountId: to,
        date: date,
        description: description,
        notes: notes,
        opKey: key,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final amount = Money.parse(_amount.text)!.abs();
    final fee = _feeValue;
    if (!await _confirmBalance(amount + fee) || !mounted) return;
    if (fee > 0 && (!await _confirmFee(amount, fee) || !mounted)) return;
    // No category picked: the keyword rules decide, falling back to "Other".
    setState(() => _saving = true);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final isTransfer = _kind == TransactionKind.transfer;
    final description = _description.text.trim().isEmpty && isTransfer ? 'Transfer' : _description.text.trim();
    final categoryId = isTransfer ? null : _categoryId;
    final toCardId = isTransfer ? _toCardId : null;
    final selected = isTransfer ? null : _selectedCategory;
    final typed = _customCategory.text.trim();
    final customCategory = (selected?.isOther ?? false) && typed.isNotEmpty ? typed : null;
    // New income from "Borrowed money" is also added to Debts.
    final addDebt = !_isEdit && _kind == TransactionKind.income && (selected?.isLoan ?? false);
    final service = ref.read(transactionServiceProvider);
    if (fee > 0) {
      _saveTransferWithFee(amount: amount, fee: fee, description: description, notes: notes);
      return;
    }
    if (!addDebt) {
      _saveOptimistically(
        service: service,
        amount: amount,
        description: description,
        categoryId: categoryId,
        customCategory: customCategory,
        toCardId: toCardId,
        notes: notes,
      );
      return;
    }
    Debt? createdDebt;
    try {
      if (_isEdit) {
        await service.update(widget.existing!.copyWith(
          amount: amount,
          kind: _kind,
          description: description,
          categoryId: () => categoryId,
          customCategory: () => customCategory,
          cardId: () => _cardId,
          toCardId: () => toCardId,
          date: _date,
          notes: () => notes,
        ));
      } else {
        await service.create(RawTransaction(
          date: _date,
          description: description,
          amount: amount,
          kind: _kind,
          source: TransactionSourceType.manual,
          cardId: _cardId,
          toCardId: toCardId,
          categoryId: categoryId,
          customCategory: customCategory,
          notes: notes,
        ));
      }
      if (addDebt) {
        final debt = Debt(
          creditor: description,
          type: DebtType.loan,
          lenderType: _loanLender,
          totalAmount: amount,
          createdAt: _date,
          notes: 'Added from income on ${DateFormat('MMM d, yyyy').format(_date)}',
        );
        final id = await ref.read(debtServiceProvider).save(debt, currencySymbol: ref.read(currencyProvider).symbol);
        createdDebt = Debt(
          id: id,
          creditor: debt.creditor,
          type: debt.type,
          lenderType: debt.lenderType,
          totalAmount: debt.totalAmount,
          createdAt: debt.createdAt,
          notes: debt.notes,
        );
      }
      ref.refreshData();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      navigator.pop();
      final d = createdDebt;
      if (d != null) {
        messenger.showSnackBar(SnackBar(
          content: Text('Also added to Debts: ${d.creditor}'),
          action: SnackBarAction(
            label: 'Add interest & due date',
            onPressed: () => navigator.push(MaterialPageRoute(builder: (_) => DebtFormScreen(existing: d))),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not save: $e', error: true);
      }
    }
  }

  /// Optimistic UI: close the form and show the transaction (and a "Saved"
  /// check) right away, then write to the database. If the write fails the
  /// change is taken back out and a message offers to try again.
  ///
  /// Runs on after this screen is gone, so it only uses things captured
  /// before closing (the provider container, the app's messenger).
  void _saveOptimistically({
    required TransactionService service,
    required int amount,
    required String description,
    required int? categoryId,
    required String? customCategory,
    required int? toCardId,
    required String? notes,
  }) {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final onError = Theme.of(context).colorScheme.onError;
    final snackText = Theme.of(context).snackBarTheme.contentTextStyle?.color;
    final pending = container.read(pendingTransactionsProvider.notifier);
    final now = DateTime.now();
    final existing = widget.existing;
    final preview = (existing ??
            TransactionEntry(
              amount: amount,
              kind: _kind,
              description: description,
              date: _date,
              source: TransactionSourceType.manual,
              affectsBalance: true,
              createdAt: now,
              updatedAt: now,
            ))
        .copyWith(
      amount: amount,
      kind: _kind,
      description: description,
      categoryId: () => categoryId,
      customCategory: () => customCategory,
      cardId: () => _cardId,
      toCardId: () => toCardId,
      date: _date,
      notes: () => notes,
      updatedAt: now,
    );
    final pendingId = existing == null ? pending.add(preview) : pending.put(preview);

    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            AnimatedCheckIcon(playOnMount: true, size: 20, color: snackText),
            const SizedBox(width: 10),
            Expanded(child: Text(existing == null ? 'Saved' : 'Changes saved')),
          ],
        ),
      ));

    Future<void> write() async {
      if (existing != null) {
        await service.update(preview);
      } else {
        await service.create(RawTransaction(
          date: _date,
          description: description,
          amount: amount,
          kind: _kind,
          source: TransactionSourceType.manual,
          cardId: _cardId,
          toCardId: toCardId,
          categoryId: categoryId,
          customCategory: customCategory,
          notes: notes,
        ));
      }
    }

    write().then((_) {
      // Reload from the database first, then drop the pending copy: the
      // lists keep showing it until the saved row arrives (no flicker).
      try {
        container.read(dataRevisionProvider.notifier).bump();
        pending.clear(pendingId);
      } catch (e) {
        debugPrint('Session closed before the save finished: $e'); // app locked meanwhile
      }
    }, onError: (Object e) {
      debugPrint('Save failed: $e');
      try {
        pending.clear(pendingId);
      } catch (_) {
        // The session was locked meanwhile; nothing left to roll back.
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: errorColor,
          duration: const Duration(seconds: 8),
          content: Text(
            'Couldn\'t save "$description", so it was taken back out. Nothing changed.',
            style: TextStyle(color: onError),
          ),
          action: SnackBarAction(
            label: 'Try again',
            textColor: onError,
            onPressed: () => navigator.push(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => existing != null
                  ? TransactionFormScreen(existing: existing)
                  : TransactionFormScreen(draft: preview),
            )),
          ),
        ));
    });
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Delete transaction?', message: 'This can\'t be undone.');
    if (!ok) return;
    try {
      await ref.read(transactionServiceProvider).delete(widget.existing!.id!);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not delete: $e', error: true);
      return;
    }
    ref.refreshData();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final cards = ref.watch(cardsProvider);
    final cardMap = ref.watch(cardMapProvider);

    // The form needs categories and accounts before it can be shown. Show a
    // spinner while they load and a retryable error if a query fails, so the
    // screen is never silently empty.
    final sources = <AsyncValue<Object>>[categories, cards, cardMap];
    final Widget body;
    // A failed background refresh keeps the last data, so typed input isn't lost.
    final failed = sources.where((v) => v.hasError && !v.hasValue).firstOrNull;
    if (failed != null) {
      debugPrint('TransactionFormScreen: could not load form data: ${failed.error}');
      body = ErrorView(
        error: failed.error!,
        onRetry: () {
          ref.invalidate(categoriesProvider);
          ref.invalidate(cardsProvider);
          ref.invalidate(cardMapProvider);
        },
      );
    } else if (sources.any((v) => !v.hasValue)) {
      body = const LoadingView();
    } else if (widget.existing?.isCapitalTransfer ?? false) {
      body = _CapitalTransferInfo(tx: widget.existing!, onDelete: _delete);
    } else {
      body = _buildForm(context, categories.requireValue, cards.requireValue, cardMap.requireValue);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'New transaction'),
        actions: [
          if (_isEdit) IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: body,
    );
  }

  /// Dropdown entries for "Cash" plus each account, with what's in them.
  List<DropdownMenuItem<int?>> _accountItems(List<PaymentCard> accounts, int? cash, String symbol) => [
        DropdownMenuItem<int?>(
          value: null,
          child: Row(children: [
            const Icon(Icons.payments_rounded),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                cash == null ? 'Cash' : 'Cash · ${Money.format(cash, symbol: symbol)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
        for (final c in accounts)
          DropdownMenuItem<int?>(
            value: c.id,
            child: Row(
              children: [
                Icon(
                  c.type == CardType.ewallet ? Icons.account_balance_wallet_rounded : Icons.credit_card_rounded,
                  color: Color(c.color),
                ),
                const SizedBox(width: 10),
                // Needs a bounded width: the dropdowns below use isExpanded.
                Flexible(
                  child: Text('${c.label} · ${Money.format(c.balance, symbol: symbol)}', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ];

  Widget _buildForm(
    BuildContext context,
    List<Category> categories,
    List<PaymentCard> cards,
    Map<int, PaymentCard> allCards,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final symbol = ref.watch(currencyProvider).symbol;
    final existing = widget.existing;
    final isTransfer = _kind == TransactionKind.transfer;
    _categoryList = categories;
    // Expense shows spending categories, income shows income types.
    final kindCategories = categories.where((c) => c.kind == _kind).toList();
    final isLoan = _kind == TransactionKind.income && (_selectedCategory?.isLoan ?? false);

    // Keep an archived card selectable when editing an old transaction.
    final accounts = [
      ...cards,
      for (final id in {_cardId, _toCardId})
        if (id != null && !cards.any((c) => c.id == id) && allCards[id] != null) allCards[id]!,
    ];
    final items = _accountItems(accounts, ref.watch(cashBalanceProvider).asDataOrNull, symbol);
    // A value that isn't in the items trips a DropdownButton assertion.
    int? safe(int? id) => accounts.any((c) => c.id == id) ? id : null;

    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          SegmentedButton<TransactionKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TransactionKind.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward_rounded)),
              ButtonSegment(value: TransactionKind.income, label: Text('Income'), icon: Icon(Icons.arrow_downward_rounded)),
              ButtonSegment(value: TransactionKind.transfer, label: Text('Transfer'), icon: Icon(Icons.swap_horiz_rounded)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              // Expense and income have different categories.
              if (_selectedCategory?.kind != _kind) {
                _categoryId = null;
                _categoryTouched = false;
              }
            }),
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
            onChanged: (_) {
              if (isTransfer && _fee.text.isNotEmpty) setState(() {});
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: switch (_kind) {
                TransactionKind.expense => 'What was it for?',
                TransactionKind.income => isLoan ? 'Who lent it to you?' : 'Where did it come from?',
                TransactionKind.transfer => 'Description (optional)',
              },
              hintText: switch (_kind) {
                TransactionKind.expense => 'e.g. Jollibee lunch',
                TransactionKind.income => isLoan ? 'e.g. Tito Ben, BPI, GCash GLoan' : 'e.g. Salary from ABC Corp',
                TransactionKind.transfer => 'e.g. Cash in to GCash',
              },
              counterText: '',
            ),
            onChanged: _onDescriptionChanged,
            validator: (v) => (!isTransfer && (v == null || v.trim().isEmpty))
                ? (_kind == TransactionKind.income ? 'Enter where it came from' : 'Enter a description')
                : null,
          ),
          if (!isTransfer) ...[
            const SizedBox(height: 20),
            Text(_kind == TransactionKind.income ? 'Type of income' : 'Category', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kindCategories)
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
            if (_selectedCategory?.isOther ?? false) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customCategory,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Type the category',
                  hintText: _kind == TransactionKind.income ? 'e.g. Freelance project' : 'e.g. Pet food',
                  counterText: '',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Type what this is for' : null,
              ),
            ],
            if (isLoan && !_isEdit) ...[
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
                      selected: _loanLender == t,
                      onSelected: (on) => setState(() => _loanLender = on ? t : null),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'This will also be added to Debts so you can track paying it back. '
                'You can add the interest and due date there.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
          const SizedBox(height: 20),
          DropdownButtonFormField<int?>(
            initialValue: safe(_cardId),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: switch (_kind) {
                TransactionKind.expense => 'Paid with',
                TransactionKind.income => 'Received in',
                TransactionKind.transfer => 'From',
              },
            ),
            items: items,
            onChanged: (v) => setState(() => _cardId = v),
          ),
          if (isTransfer) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: safe(_toCardId),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'To'),
              items: items,
              onChanged: (v) => setState(() => _toCardId = v),
              validator: (v) => v == _cardId ? 'Pick a different account to transfer to' : null,
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _fee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: 'Fee (optional)',
                  prefixText: '$symbol ',
                  helperText: 'Charged by the bank or e-wallet. Saved as a separate expense in "Fees".',
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) => (v == null || v.trim().isEmpty) ? null : validateAmount(v, allowZero: true),
              ),
              if (_feeValue > 0) ...[
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final amount = Money.parse(_amount.text)?.abs() ?? 0;
                  final fee = _feeValue;
                  return Semantics(
                    liveRegion: true,
                    child: Text(
                      '${_accountName(_cardId)} goes down by ${Money.format(amount + fee, symbol: symbol)} · '
                      '${_accountName(_toCardId)} gets ${Money.format(amount, symbol: symbol)}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  );
                }),
              ],
            ] else if (_existingFee != null)
              FutureBuilder<int>(
                future: _existingFee,
                builder: (context, snap) {
                  final fee = snap.data ?? 0;
                  if (fee == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Fee of ${Money.format(fee, symbol: symbol)} is saved separately in "Fees". '
                      'Deleting this transfer deletes the fee too.',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                  );
                },
              ),
          ],
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
          if (existing?.debtId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Added by a new debt. Edit the debt in Debts to change its amount; it updates this expense.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
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
                : Text(_isEdit ? 'Save changes' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/// Money moved into or out of business capital: shown read-only here, because it is
/// tied to the capital history. Delete it here or in Business > Capital.
class _CapitalTransferInfo extends ConsumerWidget {
  const _CapitalTransferInfo({required this.tx, required this.onDelete});
  final TransactionEntry tx;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cards = ref.watch(cardMapProvider).asDataOrNull ?? const {};
    String name(int? id) => id == null ? 'Cash' : (cards[id]?.nickname ?? 'Account');
    final out = tx.fromCapital;
    final personal = out ? name(tx.toCardId) : name(tx.cardId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(out ? 'Taken out of business capital' : 'Moved to business capital', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              AmountText(tx.amount, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${out ? 'To' : 'From'} $personal · ${DateFormat('MMM d, yyyy').format(tx.date)}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (tx.notes != null) ...[const SizedBox(height: 8), Text(tx.notes!)],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          out
              ? 'This is part of your business capital history, so it can\'t be edited. '
                  'Deleting it takes the money back out of $personal and returns it (and any fee) to capital.'
              : 'This is part of your business capital history, so it can\'t be edited. '
                  'Deleting it returns the money (and any fee) to $personal and removes it from capital.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete'),
        ),
      ],
    );
  }
}
