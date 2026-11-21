import 'package:intl/intl.dart';

/// When to remind about a debt's deadline, and what to say. Pure: no
/// plugins, so it's unit tested.
///
/// Rule: one local notification 2 days before the deadline, at 9:00 AM.
/// If that moment has already passed (the deadline is less than 2 days
/// away), remind at the next reasonable time instead of skipping it:
///  * before 9:00 AM -> today at 9:00,
///  * during the day (9:00-21:00) -> right away,
///  * at night -> tomorrow at 9:00 if that is still before the deadline
///    ends, otherwise right away.
/// After the deadline day there is no reminder (the row shows "Overdue").
class DebtReminders {
  DebtReminders._();

  static const leadDays = 2;
  static const hour = 9;
  static const quietFrom = 21;

  /// The planned reminder: deadline minus 2 days, at 9:00 AM local time.
  static DateTime plannedFor(DateTime deadline) => DateTime(deadline.year, deadline.month, deadline.day - leadDays, hour);

  /// When to fire for [deadline], seen at [now]. Null = no reminder.
  ///
  /// [allowImmediate] false is used when re-creating reminders at start-up,
  /// so a reminder already shown isn't shown again every time the app opens.
  static DateTime? scheduleTime(DateTime deadline, DateTime now, {bool allowImmediate = true}) {
    final dueEnd = DateTime(deadline.year, deadline.month, deadline.day + 1);
    if (!now.isBefore(dueEnd)) return null;
    final planned = plannedFor(deadline);
    if (planned.isAfter(now)) return planned;
    final today9 = DateTime(now.year, now.month, now.day, hour);
    final tomorrow9 = DateTime(now.year, now.month, now.day + 1, hour);
    if (now.isBefore(today9)) return today9;
    if (now.hour >= quietFrom && tomorrow9.isBefore(dueEnd)) return tomorrow9;
    if (allowImmediate) return now;
    return tomorrow9.isBefore(dueEnd) ? tomorrow9 : null;
  }

  /// "in 2 days" / "tomorrow" / "today", as seen when the reminder fires.
  static String whenText(DateTime deadline, DateTime at) {
    final days = DateTime(deadline.year, deadline.month, deadline.day)
        .difference(DateTime(at.year, at.month, at.day))
        .inDays;
    return switch (days) {
      <= 0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };
  }

  /// Notification text: "Debt due in 2 days: {name}" / "{amount} due on {date}".
  static ({String title, String body}) message({
    required String name,
    required String amountText,
    required DateTime deadline,
    required DateTime at,
  }) =>
      (
        title: 'Debt due ${whenText(deadline, at)}: $name',
        body: '$amountText due on ${DateFormat('MMM d').format(deadline)}',
      );

  /// Inline label for the debt row, or null when the deadline isn't close.
  static String? rowLabel(DateTime deadline, DateTime now) {
    final days = DateTime(deadline.year, deadline.month, deadline.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    return switch (days) {
      < 0 => 'Overdue by ${-days} day${days == -1 ? '' : 's'}',
      0 => 'Due today',
      1 => 'Due tomorrow',
      2 => 'Due in 2 days',
      _ => null,
    };
  }
}
