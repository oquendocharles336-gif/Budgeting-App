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
    if (r == null || r.applied == 0) return;
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
                Text('Collect payment · ${_order.buyer}', style: Theme.of(context).textTheme.titleLarge),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(
                    labelText: _method.isCash ? 'Cash received from buyer' : 'Amount received',
                    prefixText: '$symbol ',
                    helperText: 'Less than ${m(_due)} keeps the rest as balance due.',
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
                  onPressed: r == null || r.applied == 0 ? null : _save,
                  child: Text(r == null || r.applied == 0
                      ? 'Record payment'
                      : r.remaining == 0
                          ? 'Record ${m(r.applied)} · paid in full'
                          : 'Record ${m(r.applied)} · ${m(r.remaining)} left'),
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
