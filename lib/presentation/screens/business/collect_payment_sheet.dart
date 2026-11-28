import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/op_key.dart';
import '../../../data/models/business.dart';
import '../../../domain/business/payment_calculator.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/pending_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/optimistic.dart';
import 'order_form_screen.dart' show PaymentChangeLine;
import 'payment_qr.dart';

/// Generates quick amount chips (in centavos) for a given balance due.
/// Includes the exact amount and standard bill denominations above the balance due.
List<int> getQuickAmountChips(int due) {
  if (due <= 0) return const [];
  final result = <int>[due];
  const bills = [
    2000, // ₱20
    5000, // ₱50
    10000, // ₱100
    20000, // ₱200
    50000, // ₱500
    100000, // ₱1,000
  ];
  for (final bill in bills) {
    if (bill > due && !result.contains(bill)) {
      result.add(bill);
    }
  }
  if (due > 100000) {
    final next500 = ((due / 50000).ceil()) * 50000;
    if (next500 > due && !result.contains(next500)) {
      result.add(next500);
    }
    final next1000 = ((due / 100000).ceil()) * 100000;
    if (next1000 > due && !result.contains(next1000)) {
      result.add(next1000);
    }
  }
  return result;
}

/// Records money received for an order that still has a balance: the rest
/// of a deposit, or the whole amount for a pay-on-delivery order. Optionally
/// marks it Delivered in the same write.
///
/// Only the payment (and delivery status) change; the order's stock was
/// used when it was created and is not touched again.
Future<void> showCollectPaymentSheet(BuildContext context, BusinessOrder order, {bool markDelivered = false}) async {
  if (order.id == null || order.isCancelled || order.balanceDue <= 0) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CollectPaymentSheet(order: order, markDelivered: markDelivered),
  );
}

class _CollectPaymentSheet extends ConsumerStatefulWidget {
  const _CollectPaymentSheet({required this.order, required this.markDelivered});
  final BusinessOrder order;
  final bool markDelivered;

  @override
  ConsumerState<_CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends ConsumerState<_CollectPaymentSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late PaymentMethod _method;
  late bool _deliver;

  /// One key per sheet: a double tap or "Try again" records it once.
  final _opKey = newOpKey('order_collect');

  BusinessOrder get _order => widget.order;
  int get _due => _order.balanceDue;

  @override
  void initState() {
    super.initState();
    // The usual case: the buyer pays the whole balance.
    _amount = TextEditingController(text: Money.toInput(_due));
    _method = _order.method;
    _deliver = widget.markDelivered;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  PaymentResult? get _result {
    final v = Money.parse(_amount.text.trim())?.abs();
    if (v == null) return null;
    return PaymentCalculator.compute(total: _order.total, alreadyPaid: _order.paidAmount, tendered: v);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final r = _result;
    if (r == null || r.applied == 0 || r.isShort) return;
    final symbol = ref.read(currencyProvider).symbol;
    String m(int v) => Money.format(v, symbol: symbol);
    final order = _order;
    final method = _method;
    final tendered = r.tendered;
    final fulfillment = _deliver ? FulfillmentStatus.delivered : null;
    final paid = order.paidAmount + r.applied;
    final service = ref.read(businessServiceProvider);
    final key = _opKey;
    OptimisticWrite.run(
      context,
      savedText: [
        r.remaining == 0 ? 'Paid in full' : 'Received ${m(r.applied)} · ${m(r.remaining)} left',
        if (fulfillment != null) 'Delivered',
        if (method.isCash && r.change > 0) 'give ${m(r.change)} change',
      ].join(' · '),
      what: 'the payment from ${order.buyer}',
      show: (c) {
        final pending = c.read(pendingOrdersProvider.notifier)
          ..put(key, order.copyWith(paidAmount: paid, method: method, fulfillment: fulfillment));
        return () => pending.clear(key);
      },
      write: () => service.recordPayment(order.id!, tendered: tendered, method: method, fulfillment: fulfillment, opKey: key),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final symbol = ref.watch(currencyProvider).symbol;
    String m(int v) => Money.format(v, symbol: symbol);
    final r = _result;
    final quickChips = getQuickAmountChips(_due);
    final isInvalidOrShort = r == null || r.applied == 0 || r.isShort;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Quick Pay · ${_order.buyer}', style: Theme.of(context).textTheme.titleLarge),
                if (_order.itemsSummary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_order.itemsSummary, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 12),
                _AmountsTable(total: _order.total, paid: _order.paidAmount, due: _due, format: m),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final pm in PaymentMethod.values)
                      ChoiceChip(label: Text(pm.label), selected: _method == pm, onSelected: (_) => setState(() => _method = pm)),
                  ],
                ),
                if (_method.usesQr) ...[
                  const SizedBox(height: 12),
                  PaymentQrCard(method: _method, size: 180),
                ],
                if (quickChips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Quick amounts', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final chipVal in quickChips) ...[
                          ActionChip(
                            label: Text(
                              chipVal == _due ? 'Exact (${m(chipVal)})' : m(chipVal),
                            ),
                            onPressed: () {
                              setState(() {
                                _amount.text = Money.toInput(chipVal);
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(
                    labelText: _method.isCash ? 'Cash received from buyer' : 'Amount received',
                    prefixText: '$symbol ',
                    helperText: 'Enter cash received. Balance due is ${m(_due)}.',
                    suffixIcon: TextButton(
                      onPressed: () => setState(() => _amount.text = Money.toInput(_due)),
                      child: const Text('Exact'),
                    ),
                  ),
                  validator: (v) => validateAmount(v),
                  onChanged: (_) => setState(() {}),
                ),
                if (r != null && r.tendered > 0) ...[
                  const SizedBox(height: 10),
                  PaymentChangeLine(result: r, cash: _method.isCash),
                ],
                if (_order.fulfillment != FulfillmentStatus.delivered)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _deliver,
                    onChanged: (v) => setState(() => _deliver = v ?? false),
                    title: const Text('Also mark as Delivered'),
                    subtitle: Text('Paid on delivery', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: isInvalidOrShort ? null : _save,
                  child: Text(isInvalidOrShort
                      ? (r != null && r.isShort ? 'Shortage · enter at least ${m(_due)}' : 'Enter valid amount')
                      : r.change > 0 && _method.isCash
                          ? 'Confirm payment · give ${m(r.change)} change'
                          : 'Confirm payment · ${m(r.applied)}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Total / Paid so far / Balance due, one per line.
class _AmountsTable extends StatelessWidget {
  const _AmountsTable({required this.total, required this.paid, required this.due, required this.format});
  final int total;
  final int paid;
  final int due;
  final String Function(int) format;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: strong ? null : muted)),
              Text(value, style: strong ? const TextStyle(fontWeight: FontWeight.w800, fontSize: 18) : muted),
            ],
          ),
        );
    return Column(
      children: [
        row('Order total', format(total)),
        row('Paid so far', format(paid)),
        row('Balance due', format(due), strong: true),
      ],
    );
  }
}
