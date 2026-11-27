import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/op_key.dart';
import '../../../data/models/business.dart';
import '../../providers/business_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/pending_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/optimistic.dart';
import '../../widgets/status_badge.dart';
import 'inventory_screen.dart' show BusinessSearchField;
import 'order_form_screen.dart';

BadgeTone statusTone(OrderStatus s) => switch (s) {
      OrderStatus.paid => BadgeTone.ok,
      OrderStatus.partiallyPaid => BadgeTone.warning,
      OrderStatus.unpaid => BadgeTone.danger,
    };

BadgeTone fulfillmentTone(FulfillmentStatus f) => switch (f) {
      FulfillmentStatus.delivered => BadgeTone.ok,
      FulfillmentStatus.forPickup => BadgeTone.accent,
      FulfillmentStatus.pending => BadgeTone.neutral,
    };

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _search = '';
  OrderStatus? _status;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider((search: _search, status: _status)));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'orders_fab',
        tooltip: 'New order',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const OrderFormScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New order'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: BusinessSearchField(hint: 'Search by buyer name', onChanged: (v) => setState(() => _search = v)),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: const Text('All'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                ),
                for (final s in OrderStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = _status == s ? null : s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<BusinessOrder>>(
              value: orders,
              onRetry: () => ref.invalidate(ordersProvider((search: _search, status: _status))),
              loading: const SkeletonList(),
              data: (list) {
                if (list.isEmpty) {
                  final filtered = _search.isNotEmpty || _status != null;
                  return EmptyState(
                    icon: Icons.receipt_rounded,
                    title: filtered ? 'No matching orders' : 'No orders yet',
                    message: filtered ? 'Try another name or status.' : 'Tap "New order" to record a sale.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [for (final (i, o) in list.indexed) CascadeIn(index: i, child: OrderCard(order: o))],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class OrderCard extends ConsumerWidget {
  const OrderCard({super.key, required this.order});
  final BusinessOrder order;

  static const _cancel = 'cancel';
  static const _markPaid = 'paid';
  static const _fulfillPrefix = 'fulfill:';

  /// Delivered / For Pick-up / Pending, whatever the payment status.
  void _changeFulfillment(BuildContext context, WidgetRef ref, FulfillmentStatus f) {
    if (f == order.fulfillment) return;
    final service = ref.read(businessServiceProvider);
    final key = newOpKey('order_fulfillment');
    OptimisticWrite.run(
      context,
      savedText: f.label,
      what: 'the delivery status',
      show: (c) {
        final pending = c.read(pendingOrdersProvider.notifier)..put(key, order.copyWith(fulfillment: f));
        return () => pending.clear(key);
      },
      write: () => service.setFulfillment(order.id!, f),
    );
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, OrderStatus status) async {
    var recordFull = false;
    if (status.claimsPaid && order.balanceDue > 0) {
      // The status must not say "paid" while money is still owed.
      recordFull = await confirm(
        context,
        title: 'Record full payment?',
        message: '${order.buyer} still owes ${formatMoney(ref, order.balanceDue)}. '
            '"${status.label}" means paid in full, so the rest will be recorded as received.',
        confirmLabel: 'Record & set',
        destructive: false,
      );
      if (!recordFull) return;
    }
    if (!context.mounted) return;
    final service = ref.read(businessServiceProvider);
    final key = newOpKey('order_status');
    // Optimistic. A status change never touches stock.
    OptimisticWrite.run(
      context,
      savedText: 'Status: ${status.label}',
      what: 'the status',
      show: (c) {
        final pending = c.read(pendingOrdersProvider.notifier)
          ..put(key, order.copyWith(status: status, paidAmount: recordFull ? order.total : null));
        return () => pending.clear(key);
      },
      write: () => service.setStatus(order.id!, status, recordFullPayment: recordFull, opKey: key),
    );
  }

  Future<void> _cancelOrder(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Cancel this order?',
      message: 'Its ingredients go back into stock and it is left out of sales. Payments stay recorded.',
      confirmLabel: 'Cancel order',
    );
    if (!ok || !context.mounted) return;
    final service = ref.read(businessServiceProvider);
    final key = newOpKey('order_cancel');
    OptimisticWrite.run(
      context,
      savedText: 'Order cancelled · stock returned',
      what: 'the cancellation',
      show: (c) {
        final pending = c.read(pendingOrdersProvider.notifier)
          ..put(key, BusinessOrder.fromMap({...order.toMap(), 'cancelled_at': DateTime.now().millisecondsSinceEpoch}, order.items));
        return () => pending.clear(key);
      },
      write: () => service.cancelOrder(order.id!, opKey: key),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final saving = isUnsaved(order.id);
    final markPaidLabel = 'Mark as Paid (${formatMoney(ref, order.balanceDue)} received)';
    // Payment status, with the balance still due for a partial payment.
    final payment = switch (order.status) {
      OrderStatus.paid => const StatusBadge(label: 'Paid', tone: BadgeTone.ok, icon: Icons.check_circle_rounded),
      OrderStatus.partiallyPaid => StatusBadge(
          label: 'Partially Paid · ${formatMoney(ref, order.balanceDue)} left',
          tone: BadgeTone.warning,
          icon: Icons.timelapse_rounded,
        ),
      OrderStatus.unpaid => const StatusBadge(label: 'Unpaid', tone: BadgeTone.danger, icon: Icons.error_outline_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: saving
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => OrderFormScreen(existing: order),
                )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.buyer, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${DateFormat('MMM d').format(order.orderDate)} · ${order.method.label}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                AmountText(
                  order.total,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    decoration: order.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (!saving && !order.isCancelled)
                  PopupMenuButton<String>(
                    tooltip: 'Delivery and payment for ${order.buyer}\'s order',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      if (v == _cancel) {
                        _cancelOrder(context, ref);
                      } else if (v == _markPaid) {
                        _changeStatus(context, ref, OrderStatus.paid);
                      } else if (v.startsWith(_fulfillPrefix)) {
                        _changeFulfillment(context, ref, FulfillmentStatus.fromDb(v.substring(_fulfillPrefix.length)));
                      }
                    },
                    itemBuilder: (_) => [
                      for (final f in FulfillmentStatus.values)
                        CheckedPopupMenuItem(
                          value: '$_fulfillPrefix${f.dbValue}',
                          checked: f == order.fulfillment,
                          child: Text(f.label),
                        ),
                      const PopupMenuDivider(),
                      if (!order.status.claimsPaid)
                        PopupMenuItem(value: _markPaid, child: Text(markPaidLabel)),
                      if (!order.addedToBudget) const PopupMenuItem(value: _cancel, child: Text('Cancel order')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.itemsSummary, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (saving) const StatusBadge(label: 'Saving…', icon: Icons.sync_rounded),
                if (order.isCancelled)
                  const StatusBadge(label: 'Cancelled', tone: BadgeTone.danger, icon: Icons.block_rounded)
                else ...[
                  payment,
                  StatusBadge(
                    label: order.fulfillment.label,
                    tone: fulfillmentTone(order.fulfillment),
                    icon: fulfillmentIcon(order.fulfillment),
                  ),
                ],
                if (order.addedToBudget) const StatusBadge(label: 'In budget', tone: BadgeTone.accent, icon: Icons.savings_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
