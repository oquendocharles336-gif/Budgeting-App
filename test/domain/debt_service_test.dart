import 'package:budgeting_app/data/models/debt.dart';
import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/data/repositories/category_repository.dart';
import 'package:budgeting_app/data/repositories/debt_repository.dart';
import 'package:budgeting_app/domain/services/debt_service.dart';
import 'package:flutter_test/flutter_test.dart';

const debtCategory = 42;

class FakeCategories implements CategoryRepository {
  @override
  Future<int> debtCategoryId() async => debtCategory;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory debts + the linked expenses the service asks for.
class FakeDebts implements DebtRepository {
  final debts = <int, Debt>{};
  final expenses = <int, TransactionEntry>{}; // by debt id
  final paid = <int, int>{};
  var _nextId = 1;

  Debt _withId(Debt d, int id) => Debt.fromMap({...d.toMap(), 'id': id});

  @override
  Future<int> insert(Debt d, {TransactionEntry Function(int debtId)? linkedExpense}) async {
    final id = _nextId++;
    debts[id] = _withId(d, id);
    if (linkedExpense != null) expenses[id] = linkedExpense(id);
    return id;
  }

  @override
  Future<void> update(Debt d, {TransactionEntry Function(TransactionEntry? current)? linkedExpense}) async {
    debts[d.id!] = d;
    if (linkedExpense != null) expenses[d.id!] = linkedExpense(expenses[d.id!]);
  }

  @override
  Future<TransactionEntry?> linkedExpense(int debtId) async => expenses[debtId];

  @override
  Future<void> delete(int id, {bool removeLinkedExpense = false}) async {
    debts.remove(id);
    if (removeLinkedExpense) expenses.remove(id);
  }

  @override
  Future<List<DebtStatus>> allStatuses() async =>
      [for (final d in debts.values) DebtStatus(debt: d, paymentsTotal: paid[d.id] ?? 0)];

  @override
  Future<DebtStatus?> statusById(int id) async =>
      debts[id] == null ? null : DebtStatus(debt: debts[id]!, paymentsTotal: paid[id] ?? 0);

  @override
  Future<int> addPayment(DebtPayment p) async {
    paid[p.debtId] = (paid[p.debtId] ?? 0) + p.amount;
    return 1;
  }

  @override
  Future<void> setPaid(int debtId, bool isPaid) async => debts[debtId] = debts[debtId]!.copyWith(isPaid: isPaid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeScheduler implements DebtReminderScheduler {
  final scheduled = <int, ({DateTime at, String title, String body})>{};
  final cancelled = <int>[];

  @override
  Future<void> scheduleDebtReminder({required int debtId, required DateTime at, required String title, required String body}) async =>
      scheduled[debtId] = (at: at, title: title, body: body);

  @override
  Future<void> cancelDebtReminders(int debtId) async {
    cancelled.add(debtId);
    scheduled.remove(debtId);
  }
}

void main() {
  final now = DateTime(2026, 11, 21, 10);
  late FakeDebts repo;
  late FakeScheduler reminders;
  late DebtService service;

  setUp(() {
    repo = FakeDebts();
    reminders = FakeScheduler();
    service = DebtService(repository: repo, categories: FakeCategories(), notifications: reminders, clock: () => now);
  });

  Debt debt({bool isNew = false, DateTime? due}) => Debt(
        creditor: 'Home Credit',
        totalAmount: 1200000,
        dueDate: due,
        isNew: isNew,
        createdAt: now,
      );

  group('new vs existing', () {
    test('a NEW debt adds a linked expense in "Debt" with its amount, date and name', () async {
      final id = await service.save(debt(isNew: true), currencySymbol: '₱');
      final e = repo.expenses[id]!;
      expect(e.kind, TransactionKind.expense);
      expect(e.categoryId, debtCategory);
      expect(e.amount, 1200000);
      expect(e.date, now);
      expect(e.description, 'Home Credit');
      expect(e.debtId, id);
      // Borrowed money: not taken from an account balance.
      expect(e.affectsBalance, isFalse);
    });

    test('an EXISTING debt is only a reminder: no expense', () async {
      final id = await service.save(debt(), currencySymbol: '₱');
      expect(repo.debts[id], isNotNull);
      expect(repo.expenses, isEmpty);
    });

    test('editing a new debt updates its expense instead of adding another', () async {
      final id = await service.save(debt(isNew: true), currencySymbol: '₱');
      await service.save(repo.debts[id]!.copyWith(totalAmount: 900000, creditor: 'Home Credit (phone)'), currencySymbol: '₱');
      expect(repo.expenses, hasLength(1));
      expect(repo.expenses[id]!.amount, 900000);
      expect(repo.expenses[id]!.description, 'Home Credit (phone)');
    });

    test('a payment lowers what is left and adds no expense', () async {
      final id = await service.save(debt(isNew: true), currencySymbol: '₱');
      await service.addPayment(DebtPayment(debtId: id, amount: 200000, date: now), currencySymbol: '₱');
      expect((await repo.statusById(id))!.remaining, 1000000);
      expect(repo.expenses, hasLength(1));
    });

    test('deleting asks the repository to keep or remove the expense', () async {
      final a = await service.save(debt(isNew: true), currencySymbol: '₱');
      final b = await service.save(debt(isNew: true), currencySymbol: '₱');
      await service.delete(a);
      await service.delete(b, removeLinkedExpense: true);
      expect(repo.expenses.keys, [a]);
    });
  });

  group('reminders', () {
    test('scheduled 2 days before the deadline, at 9 AM', () async {
      final id = await service.save(debt(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      final r = reminders.scheduled[id]!;
      expect(r.at, DateTime(2026, 12, 13, 9));
      expect('${r.title}, ${r.body}', 'Debt due in 2 days: Home Credit, ₱12,000.00 due on Dec 15');
    });

    test('rescheduled when the deadline changes', () async {
      final id = await service.save(debt(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      await service.save(repo.debts[id]!.copyWith(dueDate: () => DateTime(2027, 1, 10)), currencySymbol: '₱');
      expect(reminders.scheduled[id]!.at, DateTime(2027, 1, 8, 9));
    });

    test('cancelled when paid, when the deadline is removed, and when deleted', () async {
      final a = await service.save(debt(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      await service.setPaid(a, true, currencySymbol: '₱');
      expect(reminders.scheduled.containsKey(a), isFalse);

      final b = await service.save(debt(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      await service.save(repo.debts[b]!.copyWith(dueDate: () => null), currencySymbol: '₱');
      expect(reminders.scheduled.containsKey(b), isFalse);

      final c = await service.save(debt(due: DateTime(2026, 12, 15)), currencySymbol: '₱');
      await service.delete(c);
      expect(reminders.cancelled, contains(c));
      expect(reminders.scheduled.containsKey(c), isFalse);
    });

    test('deadline tomorrow: reminded right away instead of skipped', () async {
      final id = await service.save(debt(due: DateTime(2026, 11, 22)), currencySymbol: '₱');
      expect(reminders.scheduled[id]!.at, now);
      expect(reminders.scheduled[id]!.title, 'Debt due tomorrow: Home Credit');
    });
  });
}
