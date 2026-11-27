import 'package:budgeting_app/data/models/debt.dart';
import 'package:budgeting_app/domain/debt/monthly_due.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Added on Nov 21, 2026, paid every 15th.
  final added = DateTime(2026, 11, 21, 10);
  const day = 15;
  final due = MonthlyDue(day: day, startedAt: added);

  group('dates', () {
    test('first due date is the first due day after the debt was added', () {
      expect(due.firstDue, DateTime(2026, 12, 15));
      // Added on the due day itself: first due next month.
      expect(MonthlyDue(day: 21, startedAt: added).firstDue, DateTime(2026, 12, 21));
      // Later in the same month.
      expect(MonthlyDue(day: 28, startedAt: added).firstDue, DateTime(2026, 11, 28));
    });

    test('repeats every month, across the year end', () {
      expect(due.dueAt(1), DateTime(2027, 1, 15));
      expect(due.dueAt(12), DateTime(2027, 12, 15));
    });

    test('day 31 uses the last day of shorter months', () {
      final end = MonthlyDue(day: 31, startedAt: DateTime(2027, 1, 1));
      expect(end.dueAt(0), DateTime(2027, 1, 31));
      expect(end.dueAt(1), DateTime(2027, 2, 28));
      expect(end.dueAt(2), DateTime(2027, 3, 31));
      expect(end.dueAt(3), DateTime(2027, 4, 30));
      expect(MonthlyDue(day: 30, startedAt: DateTime(2028, 2, 1)).firstDue, DateTime(2028, 2, 29));
    });
  });

  group('next due and overdue', () {
    test('before the first due date: next is that date, nothing overdue', () {
      expect(due.nextDue(DateTime(2026, 12, 1), 0), DateTime(2026, 12, 15));
      expect(due.overdueSince(DateTime(2026, 12, 1), 0), isNull);
    });

    test('on the due day it is due today, not overdue', () {
      final now = DateTime(2026, 12, 15, 20);
      expect(due.passedBy(now), 0);
      expect(due.nextDue(now, 0), DateTime(2026, 12, 15));
      expect(due.overdueSince(now, 0), isNull);
    });

    test('the day after with no payment: overdue since that date', () {
      final now = DateTime(2026, 12, 16);
      expect(due.overdueSince(now, 0), DateTime(2026, 12, 15));
      // The next reminder is already for January.
      expect(due.nextDue(now, 0), DateTime(2027, 1, 15));
    });

    test('a late payment clears the overdue month only', () {
      final now = DateTime(2026, 12, 20);
      expect(due.overdueSince(now, 1), isNull);
      expect(due.nextDue(now, 1), DateTime(2027, 1, 15));
    });

    test('paying early covers this month, so the next reminder moves on', () {
      final now = DateTime(2026, 12, 10);
      expect(due.nextDue(now, 1), DateTime(2027, 1, 15));
      expect(due.overdueSince(now, 1), isNull);
    });

    test('two missed months: overdue since the first one', () {
      final now = DateTime(2027, 2, 1);
      expect(due.passedBy(now), 2);
      expect(due.overdueSince(now, 0), DateTime(2026, 12, 15));
      expect(due.overdueSince(now, 1), DateTime(2027, 1, 15));
      expect(due.overdueSince(now, 2), isNull);
    });
  });

  group('labels', () {
    test('ordinals', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(MonthlyDue.ordinal).toList(),
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '31st']);
      expect(MonthlyDue.everyLabel(15), 'Every 15th of the month');
    });
  });

  group('DebtStatus', () {
    Debt debt({int? dueDay = day, bool paid = false}) =>
        Debt(creditor: 'Home Credit', totalAmount: 1200000, dueDay: dueDay, isPaid: paid, createdAt: added);

    test('settled debts have no next due date and are never overdue', () {
      final s = DebtStatus(debt: debt(paid: true), paymentsTotal: 0);
      expect(s.nextDue(DateTime(2027, 3, 1)), isNull);
      expect(s.isOverdue(DateTime(2027, 3, 1)), isFalse);
    });

    test('no due day: no schedule', () {
      final s = DebtStatus(debt: debt(dueDay: null), paymentsTotal: 0);
      expect(s.nextDue(DateTime(2027, 3, 1)), isNull);
      expect(s.isOverdue(DateTime(2027, 3, 1)), isFalse);
    });

    test('counts payments, one per month', () {
      final s = DebtStatus(debt: debt(), paymentsTotal: 200000, paymentsCount: 1);
      expect(s.isOverdue(DateTime(2026, 12, 20)), isFalse);
      expect(s.isOverdue(DateTime(2027, 1, 16)), isTrue);
    });

    test('a schedule anchor (dueFrom) replaces the created date', () {
      final d = debt().copyWith(dueFrom: () => DateTime(2027, 3, 1));
      expect(d.schedule!.firstDue, DateTime(2027, 3, 15));
    });

    test('an old row with only due_date reads its day as the due day', () {
      final m = {
        ...debt(dueDay: null).toMap(),
        'id': 1,
        'due_day': null,
        'due_date': DateTime(2026, 12, 9).millisecondsSinceEpoch,
      };
      expect(Debt.fromMap(m).dueDay, 9);
    });
  });
}
