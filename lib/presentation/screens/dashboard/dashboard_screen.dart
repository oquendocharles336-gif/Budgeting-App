import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/dates.dart';
import '../../../domain/budget/budget_calculator.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/activity_row.dart';
import '../../widgets/available_balance_card.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/payment_card_view.dart';
import '../analytics/analytics_screen.dart';
import '../business/business_shell.dart';
import '../cards/card_detail_screen.dart';
import '../debts/debts_screen.dart';
import '../loans/loans_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_form_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    super.key,
    required this.onSeeAllTransactions,
    required this.onOpenBudget,
    required this.onOpenWallets,
  });

  final VoidCallback onSeeAllTransactions;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenWallets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthKey = Dates.monthKey(DateTime.now());
    final summary = ref.watch(monthSummaryProvider(monthKey));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.refreshData();
            try {
              await ref.read(monthSummaryProvider(monthKey).future);
            } catch (_) {
              // The error is shown by the widget itself.
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _Header(
                onSettings: () => _push(context, const SettingsScreen()),
                onBusiness: () => _push(context, const BusinessShell()),
              ),
              const SizedBox(height: 16),
              AsyncView(
                value: summary,
                loading: const SkeletonCard(height: 190),
                data: (s) => Column(
                  children: [
                    _HeroBudgetCard(summary: s, onTap: onOpenBudget),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AvailableBalanceCard(onTap: onOpenWallets),
              const SizedBox(height: 20),
              // Import lives in Settings > Your data.
              _QuickActions(
                onDebts: () => _push(context, const DebtsScreen()),
                onInsights: () => _push(context, const AnalyticsScreen()),
                onLoans: () => _push(context, const LoansScreen()),
                onBusiness: () => _push(context, const BusinessShell()),
              ),
              const SizedBox(height: 12),
              _CardsStrip(onOpenWallets: onOpenWallets),
              const SizedBox(height: 8),
              const _DebtSummary(),
              const SizedBox(height: 8),
              SectionHeader('Recent transactions', actionLabel: 'See all', onAction: onSeeAllTransactions),
              const _RecentTransactions(),
            ],
          ),
        ),
      ),
    );
  }

  static void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings, required this.onBusiness});
  final VoidCallback onSettings;
  final VoidCallback onBusiness;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
              Text(
                DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(onPressed: onBusiness, icon: const Icon(Icons.storefront_rounded), tooltip: 'Switch to Business'),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: onSettings, icon: const Icon(Icons.settings_rounded), tooltip: 'Settings'),
      ],
    );
  }
}

class _HeroBudgetCard extends ConsumerWidget {
  const _HeroBudgetCard({required this.summary, required this.onTap});
  final MonthSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final p = summary.overall;
    final fg = scheme.onSecondaryContainer;
    // The key number is the loud 10%.
    final key = context.tokens.accentOnSecond;
    final now = DateTime.now();
    final safe = BudgetCalculator.safeDailySpend(budget: p.budget, spent: p.spent, month: summary.month, now: now);

    return Semantics(
      button: true,
      child: Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: AppTheme.heroGradient(scheme)),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.hasBudget ? (p.remaining >= 0 ? 'Left to spend in ${DateFormat('MMMM').format(now)}' : 'Over budget by') : 'Spent this month',
                    style: TextStyle(color: context.tokens.onSecondMuted, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  AmountText(
                    p.hasBudget ? p.remaining.abs() : p.spent,
                    style: TextStyle(color: key, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 16),
                  if (p.hasBudget) ...[
                    BudgetProgressBar(progress: p, onDark: true),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${formatMoney(ref, p.spent)} of ${formatMoney(ref, p.budget)} · ${p.percentUsed}%',
                            style: TextStyle(color: context.tokens.onSecondMuted, fontSize: 13),
                          ),
                        ),
                        if (safe > 0)
                          Text(
                            '${formatMoney(ref, safe)}/day',
                            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                      ],
                    ),
                    if (summary.spentByAccount.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _PaidWithLine(spent: summary.spentByAccount),
                    ],
                    // Inline, in context (no banner box): only at 80% / 100%.
                    if (p.level == BudgetLevel.warning || p.level == BudgetLevel.exceeded) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            p.level == BudgetLevel.exceeded ? Icons.error_rounded : Icons.warning_amber_rounded,
                            size: 16,
                            color: budgetColor(context, p.level),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p.level == BudgetLevel.exceeded
                                  ? 'You\'ve used your whole budget for this month.'
                                  : 'You\'ve used ${p.percentUsed}% of this month\'s budget.',
                              style: TextStyle(color: budgetColor(context, p.level), fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else
                    Row(
                      children: [
                        Icon(Icons.flag_rounded, color: fg, size: 18),
                        const SizedBox(width: 6),
                        Text('Tap to set a monthly budget', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onDebts,
    required this.onInsights,
    required this.onLoans,
    required this.onBusiness,
  });
  final VoidCallback onDebts;
  final VoidCallback onInsights;
  final VoidCallback onLoans;
  final VoidCallback onBusiness;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _Action(icon: Icons.insights_rounded, label: 'Insights', onTap: onInsights)),
          const SizedBox(width: 10),
          Expanded(child: _Action(icon: Icons.handshake_rounded, label: 'Debts', onTap: onDebts)),
          const SizedBox(width: 10),
          Expanded(child: _Action(icon: Icons.request_quote_rounded, label: 'Loans', onTap: onLoans)),
          const SizedBox(width: 10),
          Expanded(child: _Action(icon: Icons.storefront_rounded, label: 'Business', onTap: onBusiness)),
        ],
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          ExcludeSemantics(child: Icon(icon, color: scheme.primary)),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CardsStrip extends ConsumerWidget {
  const _CardsStrip({required this.onOpenWallets});
  final VoidCallback onOpenWallets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    return AsyncView(
      value: cards,
      loading: const SizedBox(height: 40),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        // Closure: each card is ~64% of the row, so the next one always
        // peeks in from the edge and the row reads as "swipe for more".
        final cardWidth = (MediaQuery.sizeOf(context).width - 32) * 0.64;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader('My cards & e-wallets', actionLabel: 'See all', onAction: onOpenWallets),
            SizedBox(
              height: cardWidth / 1.6,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => PaymentCardView(
                  card: list[i],
                  width: cardWidth,
                  subtitle: formatMoney(ref, list[i].balance),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: list[i].id!)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DebtSummary extends ConsumerWidget {
  const _DebtSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider);
    return AsyncView(
      value: debts,
      loading: const SizedBox(height: 40),
      data: (list) {
        final active = list.where((d) => !d.isSettled).toList();
        if (active.isEmpty) return const SizedBox.shrink();
        final total = active.fold<int>(0, (a, d) => a + d.remaining);
        final now = DateTime.now();
        final withDue = active.where((d) => d.debt.dueDate != null).toList()
          ..sort((a, b) => a.debt.dueDate!.compareTo(b.debt.dueDate!));
        final next = withDue.isEmpty ? null : withDue.first;
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Debts'),
            AppCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebtsScreen())),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.account_balance_rounded, color: scheme.onErrorContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total outstanding', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        AmountText(total, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        if (next != null)
                          Text(
                            next.isOverdue(now)
                                ? '${next.debt.creditor} is overdue'
                                : 'Next: ${next.debt.creditor}, ${DateFormat('MMM d').format(next.debt.dueDate!)}',
                            style: TextStyle(
                              color: next.isOverdue(now) ? scheme.error : scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text('${active.length} active', style: TextStyle(color: scheme.onSurfaceVariant)),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "Paid with: Cash ₱1,200 · GCash ₱300": every expense counts in the
/// monthly budget, whatever it was paid with.
class _PaidWithLine extends ConsumerWidget {
  const _PaidWithLine({required this.spent});
  final Map<int?, int> spent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardMapProvider).asDataOrNull ?? const {};
    final parts = [
      for (final e in spent.entries.take(3))
        '${e.key == null ? 'Cash' : (cards[e.key]?.nickname ?? 'Card')} ${formatMoney(ref, e.value)}',
      if (spent.length > 3) '+${spent.length - 3} more',
    ];
    return Text(
      'Paid with: ${parts.join(' · ')}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.tokens.onSecondMuted, fontSize: 12.5),
    );
  }
}

class _RecentTransactions extends ConsumerStatefulWidget {
  const _RecentTransactions();

  @override
  ConsumerState<_RecentTransactions> createState() => _RecentTransactionsState();
}

class _RecentTransactionsState extends ConsumerState<_RecentTransactions> {
  /// Which row floats / has its actions open (tap / swipe right).
  final _selection = ActivitySelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(recentTransactionsProvider);
    final cats = ref.watch(categoryMapProvider).asDataOrNull ?? const {};
    final cards = ref.watch(cardMapProvider).asDataOrNull ?? const {};
    return AsyncView(
      value: txs,
      data: (list) {
        if (list.isEmpty) {
          return AppCard(
            child: EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No transactions yet',
              message: 'Tap + to add your first expense, or import a card statement from Settings.',
              action: FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TransactionFormScreen()),
                ),
                child: const Text('Add expense'),
              ),
            ),
          );
        }
        // A plain glass Card (no clipping blur) so a floating row's
        // shadow and scale can rise above it.
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final t in list)
                  ActivityRow(
                    key: ValueKey('recent-${t.id}'),
                    tx: t,
                    selection: _selection,
                    category: cats[t.categoryId],
                    card: cards[t.cardId],
                    toCard: cards[t.toCardId],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
