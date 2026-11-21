import 'package:budgeting_app/domain/debt/debt_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final deadline = DateTime(2026, 12, 15, 17);

  test('reminder is the deadline minus 2 days, at 9:00 AM', () {
    expect(DebtReminders.plannedFor(deadline), DateTime(2026, 12, 13, 9));
    // Across a month boundary.
    expect(DebtReminders.plannedFor(DateTime(2026, 12, 1)), DateTime(2026, 11, 29, 9));
  });

  test('plenty of time: fires at the planned moment', () {
    expect(DebtReminders.scheduleTime(deadline, DateTime(2026, 12, 1, 10)), DateTime(2026, 12, 13, 9));
  });

  group('less than 2 days left: not skipped', () {
    test('before 9 AM -> today at 9', () {
      expect(DebtReminders.scheduleTime(deadline, DateTime(2026, 12, 14, 7)), DateTime(2026, 12, 14, 9));
    });
    test('during the day -> right away', () {
      final now = DateTime(2026, 12, 14, 13);
      expect(DebtReminders.scheduleTime(deadline, now), now);
    });
    test('at night -> tomorrow 9 AM if still before the deadline ends', () {
      expect(DebtReminders.scheduleTime(deadline, DateTime(2026, 12, 14, 22)), DateTime(2026, 12, 15, 9));
    });
    test('at night on the due day -> right away', () {
      final now = DateTime(2026, 12, 15, 22);
      expect(DebtReminders.scheduleTime(deadline, now), now);
    });
    test('on restart (no "right away") -> next 9 AM, or nothing', () {
      expect(
        DebtReminders.scheduleTime(deadline, DateTime(2026, 12, 14, 13), allowImmediate: false),
        DateTime(2026, 12, 15, 9),
      );
      expect(DebtReminders.scheduleTime(deadline, DateTime(2026, 12, 15, 13), allowImmediate: false), isNull);
    });
  });

  test('after the deadline day: no reminder', () {
    expect(DebtReminders.scheduleTime(deadline, DateTime(2026, 12, 16, 8)), isNull);
  });

  test('notification text', () {
    final m = DebtReminders.message(
      name: 'BPI loan',
      amountText: '₱5,000.00',
      deadline: deadline,
      at: DateTime(2026, 12, 13, 9),
    );
    expect('${m.title}, ${m.body}', 'Debt due in 2 days: BPI loan, ₱5,000.00 due on Dec 15');
    expect(DebtReminders.message(name: 'X', amountText: '1', deadline: deadline, at: DateTime(2026, 12, 15, 9)).title,
        'Debt due today: X');
  });

  test('inline row label', () {
    final now = DateTime(2026, 12, 13, 18);
    expect(DebtReminders.rowLabel(deadline, now), 'Due in 2 days');
    expect(DebtReminders.rowLabel(deadline, DateTime(2026, 12, 14)), 'Due tomorrow');
    expect(DebtReminders.rowLabel(deadline, DateTime(2026, 12, 10)), isNull);
    expect(DebtReminders.rowLabel(deadline, DateTime(2026, 12, 17)), 'Overdue by 2 days');
  });
}
