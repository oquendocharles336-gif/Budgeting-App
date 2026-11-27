import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../domain/analytics/data_prep.dart';
import '../../../domain/business/sales_analytics.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/business_providers.dart';
import '../../providers/core_providers.dart';
import '../../theme/app_palette.dart';
import '../../widgets/account_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/saved_snack.dart';

/// Sales analytics from cleaned orders, and "Add to Budget".
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  SalesPeriod _period = SalesPeriod.day;
  bool _adding = false;

  Future<void> _addToBudget(SalesSummary s) async {
    final symbol = ref.read(currencyProvider).symbol;
    final choice = await pickAccountSheet(
      context,
      ref,
      title: 'Add ${Money.format(s.readyForBudget, symbol: symbol)} to which account?',
      message: '${s.readyForBudgetCount} paid sale${s.readyForBudgetCount == 1 ? '' : 's'} become income in your personal budget. '
          'Each sale is added only once; unpaid sales are left out.',
    );
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final color = snackTextColor(context);
    setState(() => _adding = true);
    try {
      final r = await ref.read(businessServiceProvider).addSalesToBudget(accountId: choice.accountId);
      ref.refreshData();
      showSavedSnack(
        messenger,
        text: r.orders == 0
            ? 'Nothing new to add'
            : 'Added ${Money.format(r.amount, symbol: symbol)} from ${r.orders} sale${r.orders == 1 ? '' : 's'} to your budget',
        textColor: color,
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Could not add to budget: $e', error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(salesDataProvider);
    return AsyncView<SalesData>(
      value: data,
      onRetry: () => ref.invalidate(salesDataProvider),
      loading: const _SalesSkeleton(),
      data: (d) {
        final s = d.summary;
        if (s.orderCount == 0) {
          return const EmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'No sales yet',
            message: 'Record orders in the Orders tab. Totals and charts appear here.',
          );
        }
        final buckets = SalesAnalytics.buckets(d.orders, _period, DateTime.now());
        var row = 0;
        Widget cascade(Widget child) => CascadeIn(index: row++, child: child);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            cascade(_Tiles(summary: s)),
            cascade(_PrepLine(report: d.prepared.report)),
            const SizedBox(height: 8),
            cascade(_BudgetCard(summary: s, busy: _adding, onAdd: () => _addToBudget(s))),
            const SectionHeader('Sales over time'),
            cascade(AppCard(
              child: Column(
                children: [
                  SegmentedButton<SalesPeriod>(
                    showSelectedIcon: false,
                    segments: [for (final p in SalesPeriod.values) ButtonSegment(value: p, label: Text(p.label))],
                    selected: {_period},
                    onSelectionChanged: (v) => setState(() => _period = v.first),
                  ),
                  const SizedBox(height: 16),
                  _SalesChart(buckets: buckets),
                ],
              ),
            )),
            const SectionHeader('Best sellers'),
            cascade(AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final (i, p) in s.bestSellers.indexed)
                    ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(p.name),
                      subtitle: Text('${p.quantity} sold'),
                      trailing: AmountText(p.revenue, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            )),
            const SectionHeader('Received by payment method'),
            cascade(AppCard(child: _MethodBreakdown(summary: s))),
          ],
        );
      },
    );
  }
}

class _SalesSkeleton extends StatelessWidget {
  const _SalesSkeleton();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SkeletonCard(height: 150),
            SizedBox(height: 16),
            SkeletonCard(height: 80),
            SizedBox(height: 16),
            SkeletonCard(height: 240),
          ],
        ),
      );
}

class _Tiles extends ConsumerWidget {
  const _Tiles({required this.summary});
  final SalesSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget tile(String label, String value, {String? note}) => AppCard(
          padding: const EdgeInsets.all(14),
          child: Semantics(
            label: '$label: $value${note == null ? '' : ', $note'}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(color: context.tokens.onSecondMuted, fontSize: 13)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                if (note != null)
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.tokens.onSecondMuted, fontSize: 11.5),
                  ),
              ],
            ),
          ),
        );
    final s = summary;
    // What is still owed is the remaining balance of each order, not its
    // total: a ₱500 order with ₱200 paid adds ₱300 here.
    final owedNote = [
      if (s.partialCount > 0) '${s.partialCount} partly paid',
      if (s.unpaidCount > 0) '${s.unpaidCount} unpaid',
    ].join(' · ');
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        tile('Total sales', formatMoney(ref, s.totalSales), note: '${s.orderCount} order${s.orderCount == 1 ? '' : 's'}'),
        tile('Paid in full', '${s.paidCount}', note: s.orderCount == 0 ? null : 'of ${s.orderCount} orders'),
        tile('Collected', formatMoney(ref, s.collected)),
        tile(
          'Balance due',
          formatMoney(ref, s.unpaid),
          note: s.deliveredBalance > 0
              ? '${formatMoney(ref, s.deliveredBalance)} on delivered orders'
              : (owedNote.isEmpty ? 'Nothing owed' : owedNote),
        ),
      ],
    );
  }
}

class _PrepLine extends StatelessWidget {
  const _PrepLine({required this.report});
  final PrepReport report;

  @override
  Widget build(BuildContext context) {
    if (report.checked == 0) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Row(
        children: [
          Icon(report.changedAnything ? Icons.cleaning_services_rounded : Icons.verified_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(report.summaryOf('order'), style: TextStyle(color: color, fontSize: 12.5))),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.summary, required this.busy, required this.onAdd});
  final SalesSummary summary;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = summary.readyForBudget;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add to personal budget', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            ready == 0
                ? 'No paid sales waiting. Sales are added once they\'re paid in full, and never twice.'
                : '${formatMoney(ref, ready)} from ${summary.readyForBudgetCount} paid sale${summary.readyForBudgetCount == 1 ? '' : 's'} '
                    'not in your budget yet.',
            style: TextStyle(color: context.tokens.onSecondMuted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: ready == 0 || busy ? null : onAdd,
            icon: const Icon(Icons.savings_rounded),
            label: const Text('Add to Budget'),
          ),
        ],
      ),
    );
  }
}

class _SalesChart extends ConsumerWidget {
  const _SalesChart({required this.buckets});
  final List<SalesBucket> buckets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final symbol = ref.watch(currencyProvider).symbol;
    final values = [for (final b in buckets) b.total / 100];
    final maxV = values.fold<double>(0, math.max);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.15;
    final best = buckets.isEmpty ? null : buckets.reduce((a, b) => b.total > a.total ? b : a);
    final reduce = Cascade.reduced(context);
    return Semantics(
      label: 'Bar chart of sales. ${best == null || best.total == 0 ? 'No sales in this range' : 'Best: ${best.label}, ${Money.format(best.total, symbol: symbol)}'}.',
      child: SizedBox(
        height: 200,
        child: RepaintBoundary(child: BarChart(
          BarChartData(
            maxY: maxY,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: maxY / 4,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(Money.compact((value * 100).round(), symbol: symbol), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    // Every other label on the 14-day view so they don't overlap.
                    final show = i >= 0 && i < buckets.length && (buckets.length <= 8 || i.isEven || i == buckets.length - 1);
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(show ? buckets[i].label : '', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${buckets[group.x].label}\n${Money.format((rod.toY * 100).round(), symbol: symbol)}',
                  TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < values.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i],
                      width: buckets.length > 8 ? 8 : 16,
                      borderRadius: BorderRadius.circular(4),
                      color: i == values.length - 1 ? scheme.tertiary : scheme.primary,
                    ),
                  ],
                ),
            ],
          ),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 400),
        )),
      ),
    );
  }
}

class _MethodBreakdown extends ConsumerWidget {
  const _MethodBreakdown({required this.summary});
  final SalesSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Shares of the money received (unpaid balances aren't in any method).
    final total = summary.collected;
    if (summary.byMethod.isEmpty) {
      return Text('No payments received yet.', style: TextStyle(color: scheme.onSurfaceVariant));
    }
    return Column(
      children: [
        for (final m in summary.byMethod)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              label: '${m.method.label}: ${formatMoney(ref, m.total)} received from ${m.orders} orders',
              excludeSemantics: true,
              child: Row(
                children: [
                  SizedBox(width: 110, child: Text(m.method.label, style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : m.total / total,
                        minHeight: 12,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(scheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('${formatMoney(ref, m.total)} · ${m.orders}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
