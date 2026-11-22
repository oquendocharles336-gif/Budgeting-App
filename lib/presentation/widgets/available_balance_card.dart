import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../providers/data_providers.dart';
import '../theme/app_palette.dart';
import 'common.dart';
import 'motion/skeleton.dart';

/// "Available balance": Cash plus every debit / prepaid / e-wallet balance,
/// with two boxes under it showing each part (Cash, and Cards & e-wallets).
/// Income raises it, expenses lower it. Used on Home and Budget.
///
/// The totals come from SQL sums ([balanceSummaryProvider]), which refresh
/// after every save, so adding, editing or deleting an account or a
/// transaction updates them right away.
class AvailableBalanceCard extends ConsumerWidget {
  const AvailableBalanceCard({super.key, this.onTap, this.incomeLabel, this.income});

  final VoidCallback? onTap;

  /// Optional extra line, e.g. income received this month.
  final String? incomeLabel;
  final int? income;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(balanceSummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    return AsyncView<BalanceSummary>(
      value: summary,
      loading: const SkeletonCard(height: 150),
      onRetry: () => ref.refreshData(),
      data: (b) {
        final accounts = b.cardsAndWalletsCount;
        return AppCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                          ),
                      ],
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _BalanceBox(
                      icon: Icons.payments_rounded,
                      label: 'Cash',
                      amount: b.cash,
                      caption: 'In your pocket',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BalanceBox(
                      icon: Icons.credit_card_rounded,
                      label: 'Cards & e-wallets',
                      amount: b.cardsAndWallets,
                      caption: accounts == 0 ? 'None added yet' : '$accounts account${accounts == 1 ? '' : 's'}',
                    ),
                  ),
                ],
              ),
              if (b.hasCredit) ...[
                const SizedBox(height: 8),
                Text(
                  'Plus ${formatMoney(ref, b.availableCredit)} available credit (not counted)',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One part of the available balance: an icon, a label and its subtotal.
class _BalanceBox extends StatelessWidget {
  const _BalanceBox({required this.icon, required this.label, required this.amount, required this.caption});
  final IconData icon;
  final String label;
  final int amount;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: t.secondHigh.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(child: Icon(icon, size: 16, color: t.onSecondMuted)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.onSecondMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Long amounts shrink instead of wrapping.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(
                amount,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: amount < 0 ? scheme.error : null,
                ),
              ),
            ),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.onSecondMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
