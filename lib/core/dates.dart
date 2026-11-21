/// Small date helpers. All dates are local time.
class Dates {
  Dates._();

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

  /// First moment of the next month (exclusive end).
  static DateTime monthEnd(DateTime d) => DateTime(d.year, d.month + 1);

  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  /// "2026-11"
  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  static DateTime parseMonthKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  static DateTime previousMonth(DateTime d) => DateTime(d.year, d.month - 1);
  static DateTime nextMonth(DateTime d) => DateTime(d.year, d.month + 1);

  /// Monday of the week containing [d].
  static DateTime startOfWeek(DateTime d) {
    final day = startOfDay(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// "2026-11-21"
  static String dayKey(DateTime d) =>
      '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';
}
