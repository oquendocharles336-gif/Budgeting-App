import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/op_key.dart';
import '../../../data/models/business.dart';
import '../../../domain/business/payment_calculator.dart';
import '../../../domain/services/business_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/business_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/pending_providers.dart';
import '../../theme/app_palette.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/optimistic.dart';
import '../../widgets/status_badge.dart';
import 'payment_qr.dart';

/// New or existing buyer order: items, payment status (Unpaid / Partially
/// Paid / Paid), payment counter, method, QR and delivery / pick-up.
class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({super.key, this.existing});
  final BusinessOrder? existing;

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _buyer;
  late final TextEditingController _received;
  late final TextEditingController _notes;
  late DateTime _date;
  late List<OrderItem> _lines;
  late PaymentMethod _method;

  /// The payment status chosen. Partially Paid / Paid show the payment
  /// part of the form. What is saved always follows the money: an amount
  /// short of the total is saved as Partially Paid.
  late OrderStatus _status;

  /// Pending / For Pick-up / Delivered (independent of payment).
  late FulfillmentStatus _fulfillment;

  bool get _showPayment => _status.takesPayment;
  bool _saving = false;

  BusinessOrder? get _existing => widget.existing;

  /// A sale already added to the budget (or a cancelled order) keeps its
  /// items and payment.
  bool get _locked => (_existing?.addedToBudget ?? false) || (_existing?.isCancelled ?? false);

  /// One key per order form: a retry or double tap saves once.
  final _opKey = newOpKey('order');
  int get _alreadyPaid => _existing?.paidAmount ?? 0;
  int get _total => BusinessOrder.totalOf(_lines);

  @override
  void initState() {
    super.initState();
    final e = _existing;
    _buyer = TextEditingController(text: e?.buyer ?? '');
    _received = TextEditingController();
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.orderDate ?? DateTime.now();
    _lines = [...?e?.items];
    _method = e?.method ?? PaymentMethod.cash;
    _status = e?.status ?? OrderStatus.unpaid;
    _fulfillment = e?.fulfillment ?? FulfillmentStatus.pending;
  }

  @override
  void dispose() {
    _buyer.dispose();
    _received.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The payment counter for what's typed now (null when nothing is typed).
  PaymentResult? get _payment {
    final text = _received.text.trim();
    if (text.isEmpty) return null;
    final tendered = Money.parse(text)?.abs();
    if (tendered == null) return null;
    return PaymentCalculator.compute(total: _total, alreadyPaid: _alreadyPaid, tendered: tendered);
  }

  void _add(Product p) {
    setState(() {
      final i = _lines.indexWhere((l) => l.productId == p.id);
      if (i >= 0) {
        _lines[i] = _lines[i].copyWith(quantity: _lines[i].quantity + 1);
      } else {
        _lines.add(OrderItem(productId: p.id, name: p.name, unitPrice: p.price, quantity: 1));
      }
    });
  }

  void _setQty(int index, int qty) {
    setState(() {
      if (qty <= 0) {
        _lines.removeAt(index);
      } else {
        _lines[index] = _lines[index].copyWith(quantity: qty);
      }
    });
  }

  Future<void> _pickProduct() async {
    final products = await ref.read(productsProvider.future);
    if (!mounted) return;
    if (products.isEmpty) {
      showSnack(context, 'Add products first in the Products tab.');
      return;
    }
    final picked = await showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in products)
                ListTile(
                  minTileHeight: 64,
                  leading: PhotoThumb(path: p.photoPath, label: p.name, fallbackIcon: Icons.sell_outlined),
                  title: Text(p.name),
                  trailing: AmountText(p.price),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _add(picked);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_lines.isEmpty) {
      showSnack(context, 'Add at least one item', error: true);
      return;
    }
    final symbol = ref.read(currencyProvider).symbol;
    String m(int v) => Money.format(v, symbol: symbol);
    // Unpaid: whatever was typed in the (hidden) payment field is ignored.
    final pay = _locked || !_showPayment ? null : _payment;
    final applied = pay?.applied ?? 0;
    final paidAfter = _locked ? _alreadyPaid : (_alreadyPaid + applied).clamp(0, _total).toInt();
    // The amount received is taken off the total automatically: less than
    // the total saves as Partially Paid with the balance shown, no dialog.
    final status = BusinessService.statusFor(paidAmount: paidAfter, total: _total);
    final owesAfter = _total - paidAfter;
    final e = _existing;
    final service = ref.read(businessServiceProvider);
    // Stock: only checked when the items are new or changed (payments and
    // status never use ingredients again).
    var allowShort = false;
    final itemsChanged = e == null || !BusinessService.sameItems(e.items, _lines);
    if (itemsChanged && !_locked) {
      final List<StockShortage> short;
      try {
        short = await service.checkStock(_lines, orderId: e?.id);
      } catch (err) {
        if (mounted) showSnack(context, 'Could not check stock: $err', error: true);
        return;
      }
      if (short.isNotEmpty) {
        if (!mounted) return;
        if (!await _confirmShortStock(short)) return;
        allowShort = true;
      }
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final usedCash = pay != null && _method.isCash && applied > 0;
    final order = BusinessOrder(
      id: e?.id,
      buyer: _buyer.text.trim(),
      orderDate: _date,
      items: List.of(_lines),
      total: _total,
      paidAmount: paidAfter,
      tendered: usedCash ? pay.tendered : e?.tendered,
      changeGiven: usedCash ? pay.change : e?.changeGiven,
      method: _method,
      status: status,
      fulfillment: _fulfillment,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: e?.createdAt ?? now,
      updatedAt: now,
    );
    final key = _opKey;
    final preview = e == null
        ? BusinessOrder.fromMap({...order.toMap(), 'id': tempId()}, order.items)
        : BusinessOrder.fromMap({...order.toMap(), 'budget_tx_id': e.budgetTxId, 'cancelled_at': e.cancelledAt?.millisecondsSinceEpoch}, order.items);
    // Optimistic: the order (and any change to give) shows at once. One
    // operation key per form, so "Try again" can't create a second order
    // or take ingredients twice.
    OptimisticWrite.run(
      context,
      savedText: [
        'Saved',
        if (status == OrderStatus.partiallyPaid) 'Partially Paid, ${m(owesAfter)} left',
        if (usedCash && pay.change > 0) 'give ${m(pay.change)} change',
      ].join(' · '),
      what: '${order.buyer}\'s order',
      show: (c) {
        final pending = c.read(pendingOrdersProvider.notifier)..put(key, preview);
        return () => pending.clear(key);
      },
      write: () => service.saveOrder(order, allowShortStock: allowShort, opKey: key),
    );
    Navigator.of(context).pop();
  }

  /// Lists what's missing; "Add anyway" uses what's left (stock never
  /// goes below zero).
  Future<bool> _confirmShortStock(List<StockShortage> short) async {
    final items = {for (final i in await ref.read(inventoryRepositoryProvider).all()) i.id: i};
    if (!mounted) return false;
    final lines = [
      for (final s in short)
        '• ${items[s.itemId]?.name ?? 'Ingredient'}: needs ${formatQuantity(s.needed)}, '
            'has ${formatQuantity(s.available)} ${items[s.itemId]?.unit ?? ''}'.trimRight(),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not enough stock'),
        content: Semantics(
          liveRegion: true,
          child: Text('${lines.join('\n')}\n\n"Add anyway" uses what\'s left; stock stops at 0.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _delete() async {
    final e = _existing!;
    final ok = await confirm(
      context,
      title: 'Delete this order?',
      message: e.addedToBudget
          ? 'Its income stays in your personal budget (delete that in Activity if needed).'
          : 'This can\'t be undone.',
    );
    if (!ok) return;
    try {
      await ref.read(businessServiceProvider).deleteOrder(e.id!);
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
    String m(int v) => Money.format(v, symbol: symbol);
    final pay = _payment;
    final due = _total - _alreadyPaid > 0 ? _total - _alreadyPaid : 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New order' : 'Order'),
        actions: [
          if (_existing != null)
            IconButton(tooltip: 'Delete order', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: Form(
        key: _form,
        child: FocusTraversalGroup(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              TextFormField(
                controller: _buyer,
                autofocus: _existing == null,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Buyer name', counterText: ''),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the buyer\'s name' : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: const Text('Order date'),
                subtitle: Text(DateFormat('EEE, MMM d, yyyy').format(_date)),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 366)),
                  );
                  if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
                },
              ),
              SectionHeader('Items', actionLabel: _locked ? null : 'Add item', onAction: _locked ? null : _pickProduct),
              if (_locked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    (_existing?.isCancelled ?? false)
                        ? 'This order was cancelled, so items and payment are locked.'
                        : 'Already added to your budget, so items and payment are locked.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: OutlinedButton.icon(onPressed: _pickProduct, icon: const Icon(Icons.add_rounded), label: const Text('Add a product')),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (i, line) in _lines.indexed)
                        ListTile(
                          title: Text(line.name),
                          subtitle: Text('${m(line.unitPrice)} each · ${m(line.lineTotal)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'One less ${line.name}',
                                onPressed: _locked ? null : () => _setQty(i, line.quantity - 1),
                                icon: const Icon(Icons.remove_circle_outline_rounded),
                              ),
                              Semantics(
                                label: 'Quantity ${line.quantity}',
                                excludeSemantics: true,
                                child: SizedBox(
                                  width: 28,
                                  child: Text('${line.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              ),
                              IconButton(
                                tooltip: 'One more ${line.name}',
                                onPressed: _locked ? null : () => _setQty(i, line.quantity + 1),
                                icon: const Icon(Icons.add_circle_outline_rounded),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Total', style: Theme.of(context).textTheme.titleMedium)),
                  Text(m(_total), style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
              if (_alreadyPaid > 0) ...[
                const SizedBox(height: 4),
                _BalanceRow(paid: _alreadyPaid, balance: due),
              ],
              const SectionHeader('Payment status'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final st in OrderStatus.values)
                    ChoiceChip(
                      label: Text(st.label),
                      selected: _status == st,
                      // Money already received can't be "Unpaid" (edit
                      // the amounts instead); a locked order keeps its status.
                      onSelected: _locked || (st == OrderStatus.unpaid && _alreadyPaid > 0)
                          ? null
                          : (_) => setState(() {
                                _status = st;
                                // Paid: start with the exact balance.
                                if (st == OrderStatus.paid && _received.text.trim().isEmpty && due > 0) {
                                  _received.text = Money.toInput(due);
                                }
                              }),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  switch (_status) {
                    OrderStatus.unpaid => _alreadyPaid > 0
                        ? 'Balance due ${m(due)}. Collect it later or on delivery from the order\'s menu (Collect payment).'
                        : 'Unpaid / pay on delivery: nothing is paid now. Collect ${m(_total)} later or on delivery '
                            'from the order\'s menu (Collect payment).',
                    OrderStatus.partiallyPaid => 'Deposit / part payment: enter what the buyer paid now. It\'s taken off the total '
                        'and the balance stays due until it\'s collected (e.g. on delivery).',
                    OrderStatus.paid => 'Enter what the buyer paid. Less than the total is saved as Partially Paid.',
                  },
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              if (_showPayment) ...[
                const SectionHeader('Payment'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final pm in PaymentMethod.values)
                      ChoiceChip(
                        label: Text(pm.label),
                        selected: _method == pm,
                        onSelected: _locked ? null : (_) => setState(() => _method = pm),
                      ),
                  ],
                ),
                if (_method.usesQr && !_locked) ...[
                  const SizedBox(height: 12),
                  PaymentQrCard(method: _method),
                ],
                if (!_locked && due > 0) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _received,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(
                      labelText: _method.isCash ? 'Cash received from buyer' : 'Amount received',
                      prefixText: '$symbol ',
                      helperText: 'Less than ${m(due)}? It\'s saved as Partially Paid. Tap Exact for the full amount.',
                      helperMaxLines: 2,
                      suffixIcon: TextButton(
                        onPressed: () => setState(() => _received.text = Money.toInput(due)),
                        child: const Text('Exact'),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        // "Paid" or "Partially Paid" with nothing typed would
                        // quietly save no payment; ask instead. (An order that
                        // already has a payment can be saved as it is.)
                        return _status.takesPayment && _alreadyPaid == 0 ? 'Enter the amount received' : null;
                      }
                      return validateAmount(v, allowZero: true);
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  if (pay != null) ...[
                    const SizedBox(height: 10),
                    PaymentChangeLine(result: pay, cash: _method.isCash),
                  ],
                ],
              ],
              const SectionHeader('Delivery / pick-up'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in FulfillmentStatus.values)
                    ChoiceChip(
                      avatar: Icon(fulfillmentIcon(f), size: 18),
                      label: Text(f.label),
                      selected: _fulfillment == f,
                      onSelected: (_) => setState(() => _fulfillment = f),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Separate from payment: an order can be delivered and still unpaid.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                minLines: 1,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_existing == null ? 'Save order' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Change: ₱380" for cash, or a warning when the amount is short.
class PaymentChangeLine extends ConsumerWidget {
  const PaymentChangeLine({super.key, required this.result, required this.cash});
  final PaymentResult result;
  final bool cash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget child;
    if (result.isShort) {
      child = StatusBadge(
        label: 'Partially Paid · ${formatMoney(ref, result.remaining)} balance left',
        tone: BadgeTone.warning,
        icon: Icons.timelapse_rounded,
      );
    } else if (cash && result.change > 0) {
      child = AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text('Change to give', style: TextStyle(color: context.tokens.onSecondMuted))),
            Text(
              formatMoney(ref, result.change),
              style: TextStyle(color: context.tokens.accentOnSecond, fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    } else if (!cash && result.change > 0) {
      child = StatusBadge(
        label: 'More than the balance: ${formatMoney(ref, result.change)} extra is not counted',
        tone: BadgeTone.warning,
        icon: Icons.info_outline_rounded,
      );
    } else {
      child = const StatusBadge(label: 'Exact amount', tone: BadgeTone.ok, icon: Icons.check_circle_rounded);
    }
    return Semantics(liveRegion: true, child: child);
  }
}

/// "Paid so far ₱200 · Balance due ₱300" on an order with a payment.
class _BalanceRow extends ConsumerWidget {
  const _BalanceRow({required this.paid, required this.balance});
  final int paid;
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text('Paid so far ${formatMoney(ref, paid)}', style: TextStyle(color: scheme.onSurfaceVariant))),
        if (balance > 0)
          StatusBadge(label: 'Balance due ${formatMoney(ref, balance)}', tone: BadgeTone.warning, icon: Icons.timelapse_rounded)
        else
          const StatusBadge(label: 'Paid in full', tone: BadgeTone.ok, icon: Icons.check_circle_rounded),
      ],
    );
  }
}

/// Icon for a delivery / pick-up status (form chips and order badges).
IconData fulfillmentIcon(FulfillmentStatus f) => switch (f) {
      FulfillmentStatus.pending => Icons.schedule_rounded,
      FulfillmentStatus.forPickup => Icons.storefront_rounded,
      FulfillmentStatus.delivered => Icons.local_shipping_rounded,
    };
