import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/dates.dart';
import '../../../core/op_key.dart';
import '../../../data/models/category.dart';
import '../../../data/models/pay_later.dart';
import '../../../domain/pay_later/pay_later_rules.dart';
import '../../providers/app_state_providers.dart';
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
import 'pay_later_form_screen.dart';

/// Purchases made now and paid later. Unpaid ones are not spending yet;
/// "Paid" turns each into one real expense.
class PayLaterScreen extends ConsumerWidget {
  const PayLaterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(payLaterProvider);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    void openAdd() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PayLaterFormScreen()));
    return Scaffold(
      appBar: AppBar(title: const Text('Pay Later')),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Add Pay Later purchase',
        onPressed: openAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: CascadeScope(
        child: AsyncView<List<PayLaterItem>>(
          value: items,
          onRetry: () => ref.invalidate(payLaterProvider),
          loading: const SkeletonList(),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.schedule_rounded,
                title: 'Nothing to pay later',
                message: 'Add a purchase you\'ll pay for later. It becomes an expense when you mark it paid.',
              );
            }
            final unpaid = list.where((i) => !i.isPaid).toList();
            final paid = list.where((i) => i.isPaid).toList();
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 100 + bottomInset),
              children: [
                _TotalCard(total: PayLaterRules.totalUnpaid(list), unpaid: unpaid.length, paid: paid.length),
                const SizedBox(height: 12),
                for (final (i, item) in unpaid.indexed) CascadeIn(index: i, child: _PayLaterCard(item: item)),
                if (paid.isNotEmpty) ...[
                  const SectionHeader('Paid'),
                  for (final (i, item) in paid.indexed) CascadeIn(index: unpaid.length + i, child: _PayLaterCard(item: item)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.unpaid, required this.paid});
  final int total;
  final int unpaid;
  final int paid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: AppTheme.heroGradient(scheme), borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total unpaid', style: TextStyle(color: context.tokens.onSecondMuted)),
            const SizedBox(height: 4),
            AmountText(total, style: TextStyle(color: context.tokens.accentOnSecond, fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('$unpaid unpaid · $paid paid', style: TextStyle(color: context.tokens.onSecondMuted)),
          ],
        ),
      ),
    );
  }
}

class _PayLaterCard extends ConsumerWidget {
  const _PayLaterCard({required this.item});
  final PayLaterItem item;

  BadgeTone _tone(DateTime now) {
    final days = Dates.startOfDay(item.dueDate).difference(Dates.startOfDay(now)).inDays;
    if (days < 0) return BadgeTone.danger;
    if (days <= 2) return BadgeTone.warning;
    return BadgeTone.neutral;
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref) async {
    final choice = await pickAccountSheet(
      context,
      ref,
      title: 'Paid with',
      message: '${item.item} becomes an expense today, paid from the account you pick.',
    );
    if (choice == null || !context.mounted) return;
    final service = ref.read(payLaterServiceProvider);
    final symbol = ref.read(currencyProvider).symbol;
    final key = newOpKey('pay_later_paid');
    final now = DateTime.now();
    // Optimistic. Marking paid twice never adds a second expense: the
    // database checks the item is still unpaid inside the same transaction.
    OptimisticWrite.run(
      context,
      savedText: 'Paid · added to expenses',
      what: 'the payment for "${item.item}"',
      show: (c) {
        final pending = c.read(pendingPayLaterProvider.notifier)
          ..put(key, item.copyWith(status: PayLaterStatus.paid, paidAt: () => now));
        return () => pending.clear(key);
      },
      write: () => service.markPaid(item.id!, accountId: choice.accountId, paidAt: now),
      undo: () => SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await service.markUnpaid(item.id!, currencySymbol: symbol);
            ref.refreshData();
          } catch (e) {
            debugPrint('Undo failed: $e');
          }
        },
      ),
    );
  }

  Future<void> _markUnpaid(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Mark as unpaid?',
      message: 'The expense it created is deleted and the money goes back to the account it was paid from.',
      confirmLabel: 'Mark unpaid',
      destructive: false,
    );
    if (!ok) return;
    try {
      await ref.read(payLaterServiceProvider).markUnpaid(item.id!, currencySymbol: ref.read(currencyProvider).symbol);
      ref.refreshData();
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not change it: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cats = ref.watch(categoryMapProvider).asDataOrNull ?? const <int, Category>{};
    final category = cats[item.categoryId];
    final saving = isUnsaved(item.id);
    final now = DateTime.now();
    final fmt = DateFormat('MMM d');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: saving ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayLaterFormScreen(existing: item))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryAvatar(category: category, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.item, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${category?.name ?? 'Uncategorized'} · bought ${fmt.format(item.purchaseDate)}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AmountText(item.amount, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: item.isPaid
                        ? StatusBadge(
                            label: 'Paid ${item.paidAt == null ? '' : fmt.format(item.paidAt!)}'.trim(),
                            tone: BadgeTone.ok,
                            icon: Icons.check_circle_rounded,
                          )
                        : StatusBadge(
                            label: PayLaterRules.dueLabel(item.dueDate, now),
                            tone: _tone(now),
                            icon: Icons.event_rounded,
                          ),
                  ),
                ),
                if (saving)
                  const StatusBadge(label: 'Saving…', icon: Icons.sync_rounded)
                else if (item.isPaid)
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => _markUnpaid(context, ref),
                    child: const Text('Mark unpaid'),
                  )
                else
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
                    onPressed: () => _markPaid(context, ref),
                    icon: const Icon(Icons.check_rounded),
                    label: Text('Paid', semanticsLabel: 'Mark ${item.item} as paid'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
