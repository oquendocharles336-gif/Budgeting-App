import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/debt.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'debt_detail_screen.dart';
import 'debt_form_screen.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Debts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebtFormScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add debt'),
      ),
      body: AsyncView<List<DebtStatus>>(
        value: debts,
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.handshake_rounded,
              title: 'No debts',
              message: 'Track money you owe: loans, installments, or that ₱500 from a friend.',
            );
          }
          final open = list.where((d) => !d.isSettled).toList();
          final paid = list.where((d) => d.isSettled).toList();
          final total = open.fold<int>(0, (a, d) => a + d.remaining);
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient(scheme),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total outstanding', style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85))),
                    const SizedBox(height: 4),
                    AmountText(total, style: TextStyle(color: scheme.onPrimary, fontSize: 32, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${open.length} open · ${paid.length} paid',
                      style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final d in open) _DebtCard(status: d),
              if (paid.isNotEmpty) ...[
                const SectionHeader('Paid off'),
                for (final d in paid) _DebtCard(status: d),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DebtCard extends ConsumerWidget {
  const _DebtCard({required this.status});
  final DebtStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = status.debt;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final overdue = status.isOverdue(now);
    String? dueText;
    if (d.dueDate != null && !status.isSettled) {
      final days = DateTime(d.dueDate!.year, d.dueDate!.month, d.dueDate!.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      dueText = days < 0
          ? 'Overdue by ${-days} day${days == -1 ? '' : 's'}'
          : days == 0
              ? 'Due today'
              : days == 1
                  ? 'Due tomorrow'
                  : 'Due ${DateFormat('MMM d').format(d.dueDate!)}';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: d.id!))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(d.creditor, style: Theme.of(context).textTheme.titleMedium)),
                if (status.isSettled)
                  Icon(Icons.check_circle_rounded, color: StatusColors.ok(context))
                else
                  AmountText(status.remaining, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: status.progress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(StatusColors.ok(context)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatMoney(ref, status.paid)} paid of ${formatMoney(ref, d.totalAmount)}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ),
                if (dueText != null)
                  Text(
                    dueText,
                    style: TextStyle(
                      color: overdue ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
