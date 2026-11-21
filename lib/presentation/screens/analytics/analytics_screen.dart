import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models/category.dart';
import '../../../domain/analytics/spending_analytics.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final data = ref.watch(analyticsProvider(Dates.monthKey(month)));
    final cats = ref.watch(categoryMapProvider).asDataOrNull ?? const <int, Category>{};
    final notifier = ref.read(selectedMonthProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          MonthSwitcher(month: month, onPrevious: notifier.previous, onNext: notifier.next),
          AsyncView<AnalyticsData>(
            value: data,
            onRetry: () => ref.refreshData(),
            data: (a) {
              if (a.total == 0) {
                return const EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'No spending this month',
                  message: 'Charts appear once you add expenses.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryGrid(data: a),
                  const SectionHeader('Daily spending'),
                  AppCard(child: _DailyChart(data: a)),
                  const SectionHeader('By category'),
                  AppCard(child: _CategoryDonut(data: a, categories: cats)),
                  const SectionHeader('Weeks of the month'),
                  AppCard(child: _WeeksList(data: a)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends ConsumerWidget {
  const _SummaryGrid({required this.data});
  final AnalyticsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = Dates.monthKey(data.month) == Dates.monthKey(DateTime.now());
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _Tile(label: 'Total spent', value: formatMoney(ref, data.total), sub: '${data.transactionCount} expenses'),
        _Tile(label: 'Average per day', value: formatMoney(ref, data.averageDaily)),
        _Tile(label: 'vs last month', value: _change(data.monthComparison), sub: formatMoney(ref, data.previousMonthTotal), comparison: data.monthComparison),
        if (isCurrent)
          _Tile(label: 'This week vs last', value: _change(data.week), sub: formatMoney(ref, data.week.current), comparison: data.week)
        else
          _Tile(label: 'Top category share', value: data.total == 0 || data.byCategory.isEmpty ? '–' : '${(data.byCategory.first.total * 100 / data.total).round()}%'),
      ],
    );
  }

  static String _change(PeriodComparison c) {
    final r = c.changeRatio;
    if (r == null) return c.current == 0 ? '–' : 'New';
    final pct = (r * 100).round();
    return '${pct > 0 ? '+' : ''}$pct%';
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.sub, this.comparison});
  final String label;
  final String value;
  final String? sub;
  final PeriodComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color? valueColor;
    IconData? icon;
    final c = comparison;
    if (c != null && c.changeRatio != null && c.difference != 0) {
      // Spending more is "bad" (red), spending less is "good" (green).
      valueColor = c.difference > 0 ? StatusColors.danger(context) : StatusColors.ok(context);
      icon = c.difference > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    }
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: valueColor), const SizedBox(width: 4)],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor)),
                ),
              ),
            ],
          ),
          if (sub != null)
            Text(sub!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _DailyChart extends ConsumerWidget {
  const _DailyChart({required this.data});
  final AnalyticsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final symbol = ref.watch(currencyProvider).symbol;
    final values = data.daily.map((c) => c / 100).toList();
    final maxV = values.fold<double>(0, math.max);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.15;
    final avg = data.averageDaily / 100;
    final now = DateTime.now();

    return Semantics(
      label: 'Bar chart of daily spending. Highest day ${Money.format((maxV * 100).round(), symbol: symbol)}.',
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceBetween,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
            ),
            extraLinesData: ExtraLinesData(horizontalLines: [
              if (avg > 0)
                HorizontalLine(
                  y: avg,
                  color: scheme.tertiary,
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    style: TextStyle(color: scheme.tertiary, fontSize: 11, fontWeight: FontWeight.w600),
                    labelResolver: (_) => 'avg',
                  ),
                ),
            ]),
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
                    child: Text(
                      Money.compact((value * 100).round(), symbol: symbol),
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final day = value.toInt() + 1;
                    final show = day == 1 || day % 5 == 0;
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(show ? '$day' : '', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  'Day ${group.x + 1}\n${Money.format((rod.toY * 100).round(), symbol: symbol)}',
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
                      width: 6,
                      borderRadius: BorderRadius.circular(3),
                      color: (data.month.year == now.year && data.month.month == now.month && i + 1 == now.day)
                          ? scheme.tertiary
                          : scheme.primary,
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 400),
        ),
      ),
    );
  }
}

class _CategoryDonut extends ConsumerStatefulWidget {
  const _CategoryDonut({required this.data, required this.categories});
  final AnalyticsData data;
  final Map<int, Category> categories;

  @override
  ConsumerState<_CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends ConsumerState<_CategoryDonut> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.data.total;
    final items = widget.data.byCategory;
    // Top 5 + everything else grouped, so the donut stays readable.
    final top = items.take(5).toList();
    final rest = items.skip(5).fold<int>(0, (a, c) => a + c.total);
    final slices = <({String name, int total, Color color, Category? cat})>[
      for (final c in top)
        (
          name: widget.categories[c.categoryId]?.name ?? 'Uncategorized',
          total: c.total,
          color: Color(widget.categories[c.categoryId]?.color ?? 0xFF78909C),
          cat: widget.categories[c.categoryId],
        ),
      if (rest > 0) (name: 'Everything else', total: rest, color: scheme.outline, cat: null),
    ];
    final focus = _touched != null && _touched! < slices.length ? slices[_touched!] : null;

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 62,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions || response?.touchedSection == null) {
                        if (_touched != null) setState(() => _touched = null);
                        return;
                      }
                      final i = response!.touchedSection!.touchedSectionIndex;
                      if (i != _touched) setState(() => _touched = i < 0 ? null : i);
                    },
                  ),
                  sections: [
                    for (var i = 0; i < slices.length; i++)
                      PieChartSectionData(
                        value: slices[i].total.toDouble(),
                        color: slices[i].color,
                        radius: _touched == i ? 34 : 28,
                        showTitle: false,
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 300),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(focus?.name ?? 'Total', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  AmountText(focus?.total ?? total, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                s.cat != null
                    ? CategoryAvatar(category: s.cat, size: 32)
                    : Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: s.color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.more_horiz_rounded, color: s.color, size: 18),
                      ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${(s.total * 100 / total).round()}%', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AmountText(s.total, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WeeksList extends ConsumerWidget {
  const _WeeksList({required this.data});
  final AnalyticsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final maxWeek = data.weeks.fold<int>(0, (m, w) => math.max(m, w.total));
    return Column(
      children: [
        for (final w in data.weeks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 64, child: Text('Days ${w.label}', style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: maxWeek == 0 ? 0 : w.total / maxWeek,
                      minHeight: 12,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(formatMoney(ref, w.total), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
