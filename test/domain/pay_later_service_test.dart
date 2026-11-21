import 'package:budgeting_app/data/models/pay_later.dart';
import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/data/repositories/pay_later_repository.dart';
import 'package:budgeting_app/domain/pay_later/pay_later_rules.dart';
import 'package:budgeting_app/domain/services/pay_later_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory items + the expenses "Paid" creates. Mirrors the real
/// repository: markPaid re-reads the item and does nothing if it is
/// already paid.
class FakePayLater implements PayLaterRepository {
  final items = <int, PayLaterItem>{};
  final expenses = <int, TransactionEntry>{};
  var _nextId = 1;
  var _nextTx = 100;

  @override
  Future<List<PayLaterItem>> all() async => items.values.toList();

  @override
  Future<PayLaterItem?> byId(int id) async => items[id];

  final _ops = <String, int>{};

  @override
  Future<int> insert(PayLaterItem p, {String? opKey}) async {
    // Same rule as OpGuard: a key that already ran returns its first id.
    if (opKey != null && _ops.containsKey(opKey)) return _ops[opKey]!;
    final id = _nextId++;
    items[id] = p.copyWith(id: id);
    if (opKey != null) _ops[opKey] = id;
    return id;
  }

  @override
  Future<void> update(PayLaterItem p) async {
    final old = items[p.id]!;
    items[p.id!] = p.copyWith(status: old.status, paidAt: () => old.paidAt, expenseTxId: () => old.expenseTxId);
  }

  @override
  Future<MarkPaidResult> markPaid(
    int id, {
    required DateTime paidAt,
    required TransactionEntry Function(PayLaterItem item) expenseFor,
  }) async {
    final item = items[id]!;
    if (item.isPaid) return (expenseId: item.expenseTxId ?? -1, alreadyPaid: true);
    final txId = _nextTx++;
    expenses[txId] = expenseFor(item);
    items[id] = item.copyWith(status: PayLaterStatus.paid, paidAt: () => paidAt, expenseTxId: () => txId);
    return (expenseId: txId, alreadyPaid: false);
  }

  @override
  Future<void> markUnpaid(int id) async {
    final item = items[id]!;
    if (!item.isPaid) return;
    expenses.remove(item.expenseTxId);
    items[id] = item.copyWith(status: PayLaterStatus.unpaid, paidAt: () => null, expenseTxId: () => null);
  }

  @override
  Future<void> delete(int id, {bool removeExpense = false}) async {
    final item = items.remove(id);
    if (removeExpense) expenses.remove(item?.expenseTxId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReminders implements PayLaterReminderScheduler {
  final scheduled = <int, ({DateTime at, String title, String body})>{};
  final cancelled = <int>[];

  @override
  Future<void> schedulePayLaterReminder({required int itemId, required DateTime at, required String title, required String body}) async =>
      scheduled[itemId] = (at: at, title: title, body: body);

  @override
  Future<void> cancelPayLaterReminder(int itemId) async {
    cancelled.add(itemId);
    scheduled.remove(itemId);
  }
}

void main() {
  final now = DateTime(2026, 11, 21, 10);
  late FakePayLater repo;
  late FakeReminders reminders;
  late PayLaterService service;

  setUp(() {
    repo = FakePayLater();
    reminders = FakeReminders();
    service = PayLaterService(repository: repo, notifications: reminders, clock: () => now);
  });

  PayLaterItem item({DateTime? due, int amount = 499900}) => PayLaterItem(
        item: 'Rice cooker',
        amount: amount,
        categoryId: 4,
        purchaseDate: DateTime(2026, 11, 20),
        dueDate: due ?? DateTime(2026, 12, 15),
        createdAt: now,
        updatedAt: now,
      );

  group('Pay Later to expense', () {
    test('unpaid items are not spending', () async {
      await service.save(item(), currencySymbol: '₱');
      expect(repo.expenses, isEmpty);
    });

    test('"Paid" creates one expense with the amount, category, account and paid date', () async {
      final id = await service.save(item(), currencySymbol: '₱');
      final result = await service.markPaid(id, accountId: 3);
      expect(result.alreadyPaid, isFalse);
      expect(repo.expenses, hasLength(1));
      final e = repo.expenses.values.single;
      expect(e.kind, TransactionKind.expense);
      expect(e.amount, 499900);
      expect(e.categoryId, 4);
      expect(e.cardId, 3);
      expect(e.date, now);
      expect(e.description, 'Rice cooker');
      // Typed-in money: it moves the paying account's balance.
      expect(e.affectsBalance, isTrue);
      expect(repo.items[id]!.isPaid, isTrue);
      expect(repo.items[id]!.expenseTxId, result.expenseId);
    });

    test('marking paid twice never adds a second expense', () async {
      final id = await service.save(item(), currencySymbol: '₱');
      final first = await service.markPaid(id, accountId: null);
      final second = await service.markPaid(id, accountId: null);
      expect(second.alreadyPaid, isTrue);
      expect(second.expenseId, first.expenseId);
      expect(repo.expenses, hasLength(1));
    });

    test('undo removes the expense; paying again adds exactly one', () async {
      final id = await service.save(item(), currencySymbol: '₱');
      await service.markPaid(id, accountId: null);
      await service.markUnpaid(id, currencySymbol: '₱');
      expect(repo.expenses, isEmpty);
      expect(repo.items[id]!.isPaid, isFalse);
      await service.markPaid(id, accountId: null);
      expect(repo.expenses, hasLength(1));
    });

    test('editing a paid item does not add or change expenses', () async {
      final id = await service.save(item(), currencySymbol: '₱');
      await service.markPaid(id, accountId: null);
      await service.save(repo.items[id]!.copyWith(notes: () => 'Lazada'), currencySymbol: '₱');
      expect(repo.expenses, hasLength(1));
      expect(repo.items[id]!.isPaid, isTrue);
    });

    test('retrying an add with the same key saves it once', () async {
      final a = await service.save(item(), currencySymbol: '₱', opKey: 'add-1');
      final b = await service.save(item(), currencySymbol: '₱', opKey: 'add-1');
      expect(b, a);
      expect(repo.items, hasLength(1));
    });

    test('no category falls back to "Other"', () {
      final e = PayLaterRules.expenseFor(
        item().copyWith(categoryId: () => null),
        accountId: null,
        paidAt: now,
        fallbackCategoryId: 8,
        now: now,
      );
      expect(e.categoryId, 8);
    });
  });

  group('reminders (same rules as debts)', () {
    test('scheduled 2 days before the due date at 9:00 AM', () async {
      final id = await service.save(item(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      expect(reminders.scheduled[id]!.at, DateTime(2026, 12, 13, 9));
      expect(reminders.scheduled[id]!.title, 'Pay Later due in 2 days: Rice cooker');
    });

    test('rescheduled when the due date changes', () async {
      final id = await service.save(item(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      await service.save(repo.items[id]!.copyWith(dueDate: DateTime(2026, 12, 31)), currencySymbol: '₱');
      expect(reminders.scheduled[id]!.at, DateTime(2026, 12, 29, 9));
    });

    test('cancelled when paid', () async {
      final id = await service.save(item(), currencySymbol: '₱');
      await service.markPaid(id, accountId: null);
      expect(reminders.scheduled.containsKey(id), isFalse);
      expect(reminders.cancelled, contains(id));
    });

    test('cancelled when deleted', () async {
      final id = await service.save(item(), currencySymbol: '₱');
      await service.delete(id);
      expect(reminders.scheduled.containsKey(id), isFalse);
      expect(reminders.cancelled, contains(id));
    });

    test('back after undoing "Paid"', () async {
      final id = await service.save(item(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      await service.markPaid(id, accountId: null);
      await service.markUnpaid(id, currencySymbol: '₱');
      expect(reminders.scheduled[id]!.at, DateTime(2026, 12, 13, 9));
    });
  });

  group('labels', () {
    test('"Due in X days" and friends', () {
      expect(PayLaterRules.dueLabel(DateTime(2026, 11, 26), now), 'Due in 5 days');
      expect(PayLaterRules.dueLabel(DateTime(2026, 11, 22), now), 'Due tomorrow');
      expect(PayLaterRules.dueLabel(DateTime(2026, 11, 21, 23), now), 'Due today');
      expect(PayLaterRules.dueLabel(DateTime(2026, 11, 19), now), 'Overdue by 2 days');
    });

    test('total unpaid ignores paid items', () {
      final a = item(amount: 1000);
      final b = item(amount: 500).copyWith(status: PayLaterStatus.paid);
      expect(PayLaterRules.totalUnpaid([a, b]), 1000);
    });
  });
}
