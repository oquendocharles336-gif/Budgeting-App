import '../../core/dates.dart';

/// Which months Insights may show: from the first month that has chart
/// data up to the current month. Months before that would be empty, so the
/// previous button, swiping and the month picker all stop there.
class InsightsRange {
  const InsightsRange({required this.earliest, required this.latest});

  /// [earliestData]: the first day with spending (null = no data yet, so
  /// only the current month is reachable).
  factory InsightsRange.from(DateTime? earliestData, DateTime now) {
    final latest = Dates.monthStart(now);
    var earliest = Dates.monthStart(earliestData ?? now);
    // A future-dated first expense can't push the start past today.
    if (earliest.isAfter(latest)) earliest = latest;
    return InsightsRange(earliest: earliest, latest: latest);
  }

  /// First day of the earliest month with data.
  final DateTime earliest;

  /// First day of the current month.
  final DateTime latest;

  bool canGoBack(DateTime month) => Dates.monthStart(month).isAfter(earliest);
  bool canGoForward(DateTime month) => Dates.monthStart(month).isBefore(latest);
  bool contains(DateTime month) {
    final m = Dates.monthStart(month);
    return !m.isBefore(earliest) && !m.isAfter(latest);
  }

  /// [month] moved inside the range.
  DateTime clamp(DateTime month) {
    final m = Dates.monthStart(month);
    if (m.isBefore(earliest)) return earliest;
    if (m.isAfter(latest)) return latest;
    return m;
  }

  /// Bounds for a date picker on the Insights screen.
  DateTime get firstPickable => earliest;
  DateTime lastPickable(DateTime now) => Dates.startOfDay(now);
}
