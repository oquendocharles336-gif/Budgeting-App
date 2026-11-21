import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../providers/data_providers.dart';
import 'common.dart';
import 'motion/skeleton.dart';

/// "Available balance": Cash plus every bank / e-wallet balance. Income
/// raises it, expenses lower it. Used on Home and Budget.
class AvailableBalanceCard extends ConsumerWidget {
  const AvailableBalanceCard({super.key, this.onTap, this.incomeLabel, this.income});

  final VoidCallback? onTap;

  /// Optional second line, e.g. income received this month.
  final String? incomeLabel;
  final int? income;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(balanceSummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    return AsyncView<BalanceSummary>(
      value: summary,
      loading: const SkeletonCard(height: 76),
      onRetry: () => ref.refreshData(),
      data: (b) => AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.account_balance_wallet_rounded, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available balance', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  AmountText(
                    b.available,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: b.available < 0 ? scheme.error : null,
                    ),
                  ),
                  if (incomeLabel != null && income != null)
                    Text(
                      '$incomeLabel ${formatMoney(ref, income!)}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    )
                  else
                    Text(
                      'Cash ${formatMoney(ref, b.cash)} · ${b.accounts.length} account${b.accounts.length == 1 ? '' : 's'}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
