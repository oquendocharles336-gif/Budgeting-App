import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
      OrderStatus.complete || OrderStatus.paid => BadgeTone.ok,
      OrderStatus.delivered => BadgeTone.accent,
      OrderStatus.deliveredNotPaid => BadgeTone.warning,
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
    final payment = order.isFullyPaid
        ? const StatusBadge(label: 'Paid in full', tone: BadgeTone.ok, icon: Icons.check_circle_rounded)
        : order.isPartiallyPaid
            ? StatusBadge(label: '${formatMoney(ref, order.balanceDue)} left', tone: BadgeTone.warning, icon: Icons.timelapse_rounded)
            : const StatusBadge(label: 'Unpaid', tone: BadgeTone.danger, icon: Icons.error_outline_rounded);
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
                    tooltip: 'Change status of ${order.buyer}\'s order',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      if (v == _cancel) {
                        _cancelOrder(context, ref);
                      } else {
                        _changeStatus(context, ref, OrderStatus.fromDb(v));
                      }
                    },
                    itemBuilder: (_) => [
                      for (final s in OrderStatus.values)
                        CheckedPopupMenuItem(value: s.dbValue, checked: s == order.status, child: Text(s.label)),
                      const PopupMenuDivider(),
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
                  StatusBadge(label: order.status.label, tone: statusTone(order.status)),
                  payment,
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
