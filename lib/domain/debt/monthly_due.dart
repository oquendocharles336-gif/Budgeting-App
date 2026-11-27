import 'dart:math' as math;

/// A debt paid on the same day every month ("every 15th"). Pure: no
/// plugins or database, so it's unit tested.
///
/// Rules:
///  * The first due date is the first [day] strictly after [startedAt]
///    (a debt added on the 15th with day 15 is first due next month).
///  * In a shorter month the last day is used (day 31 -> Feb 28/29,
///    Apr 30), so a month is never skipped.
///  * One recorded payment covers one month, oldest month first. Paying
///    early (before the due date) covers that month, so the next reminder
///    moves to the month after.
///  * A due date has "passed" once its day is over; on the day itself it
///    is "due today", not overdue.
class MonthlyDue {
  const MonthlyDue({required this.day, required this.startedAt}) : assert(day >= 1 && day <= 31);

  /// Day of the month, 1-31.
  final int day;

  /// When counting starts (usually when the debt was added).
  final DateTime startedAt;

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// [day] in the given month, moved to the month's last day if needed.
  /// [month] may be outside 1-12 (it rolls over like [DateTime]).
  static DateTime dateIn(int year, int month, int day) {
    final first = DateTime(year, month);
    return DateTime(first.year, first.month, math.min(day, daysInMonth(first.year, first.month)));
  }

  static int _monthIndex(DateTime d) => d.year * 12 + d.month - 1;
  static DateTime _fromIndex(int index, int day) => dateIn(index ~/ 12, index % 12 + 1, day);
  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Month index (year * 12 + month - 1) of the first due date.
  int get _firstIndex {
    final start = _startOfDay(startedAt);
    var i = _monthIndex(start);
    if (!_fromIndex(i, day).isAfter(start)) i++;
    return i;
  }

  /// The first due date.
  DateTime get firstDue => dueAt(0);

  /// The [n]th due date (0 = the first).
  DateTime dueAt(int n) => _fromIndex(_firstIndex + n, day);

  /// How many due dates are over (their day has ended) at [now].
  int passedBy(DateTime now) {
    final today = _startOfDay(now);
    final first = _firstIndex;
    final current = _monthIndex(today);
    if (current < first) return 0;
    var n = current - first; // every earlier month's due date has passed
    if (dueAt(n).isBefore(today)) n++; // and this month's, once its day is over
    return n;
  }

  /// The due date the next reminder is for: today or later, after the
  /// months already covered by [paymentsCount] payments.
  DateTime nextDue(DateTime now, int paymentsCount) => dueAt(math.max(math.max(paymentsCount, 0), passedBy(now)));

  /// The oldest due date that passed without a payment, or null when every
  /// passed month is covered.
  DateTime? overdueSince(DateTime now, int paymentsCount) {
    final paid = math.max(paymentsCount, 0);
    return passedBy(now) > paid ? dueAt(paid) : null;
  }

  /// "Every 15th of the month".
  String get label => everyLabel(day);

  static String everyLabel(int day) => 'Every ${ordinal(day)} of the month';

  /// 1st, 2nd, 3rd, 4th ... 11th, 12th, 13th ... 21st, 22nd, 23rd, 31st.
  static String ordinal(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}
