import 'package:flutter/foundation.dart';

import '../../core/money.dart';
import '../../data/models/debt.dart';
import '../../data/models/transaction_entry.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/debt_repository.dart';
import '../debt/debt_reminder.dart';

/// What the debt logic needs from the notification plugin (a fake in tests).
abstract interface class DebtReminderScheduler {
  Future<void> scheduleDebtReminder({
    required int debtId,
    required DateTime at,
    required String title,
    required String body,
  });

  Future<void> cancelDebtReminders(int debtId);
}

/// Debt changes, the expense a new debt creates, and deadline reminders.
///
/// * **New debt** (money just received or spent): also saved as an expense
///   in the "Debt" category with the debt's amount, date and name, linked
///   by `transactions.debt_id`, so it counts in the monthly budget and
///   analytics. Editing the debt updates that expense.
/// * **Existing debt**: only a reminder. It's in the debt list and total,
///   but creates no expense and doesn't touch budget or analytics.
/// * **Payments** are recorded against the debt only (remaining balance and
///   total debt go down). They never create a new expense, so the money
///   isn't counted twice.
class DebtService {
  DebtService({
    required DebtRepository repository,
    required this._categories,
    required this._notifications,
    DateTime Function()? clock,
  })  : _repo = repository,
        _clock = clock ?? DateTime.now;

  final DebtRepository _repo;
  final CategoryRepository _categories;
  final DebtReminderScheduler _notifications;
  final DateTime Function() _clock;

  /// The expense a new debt adds. Not paid from an account (it's borrowed
  /// or bought on credit), so it never moves account balances.
  static TransactionEntry linkedExpenseFor(
    Debt debt, {
    required int debtId,
    required int categoryId,
    required DateTime now,
    TransactionEntry? current,
  }) {
    final base = TransactionEntry(
      id: current?.id,
      amount: debt.totalAmount,
      kind: TransactionKind.expense,
      description: debt.creditor.trim(),
      categoryId: categoryId,
      date: debt.createdAt,
      notes: 'Added from a new debt',
      source: TransactionSourceType.manual,
      affectsBalance: false,
      debtId: debtId,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );
    // Keep a category the user picked for it later.
    return current == null ? base : base.copyWith(categoryId: () => current.categoryId ?? categoryId);
  }

  Future<int> save(Debt debt, {required String currencySymbol}) async {
    if (debt.creditor.trim().isEmpty) throw ArgumentError('Creditor is required');
    if (debt.totalAmount <= 0) throw ArgumentError('Total must be more than zero');
    if (debt.initialPaid < 0 || debt.initialPaid > debt.totalAmount) {
      throw ArgumentError('Amount already paid must be between zero and the total');
    }
    final now = _clock();
    final int id;
    var deadlineChanged = true;
    if (debt.id == null) {
      final categoryId = debt.isNew ? await _categories.debtCategoryId() : null;
      id = await _repo.insert(
        debt,
        linkedExpense: debt.isNew
            ? (debtId) => linkedExpenseFor(debt, debtId: debtId, categoryId: categoryId!, now: now)
            : null,
      );
    } else {
      id = debt.id!;
      final before = await _repo.statusById(id);
      deadlineChanged = before?.debt.dueDate != debt.dueDate;
      final categoryId = debt.isNew ? await _categories.debtCategoryId() : null;
      await _repo.update(
        debt,
        linkedExpense: debt.isNew
            ? (current) => linkedExpenseFor(debt, debtId: id, categoryId: categoryId!, now: now, current: current)
            : null,
      );
    }
    // Notify right away only when the deadline is new or moved, not on every edit.
    await _sync(id, currencySymbol, allowImmediate: deadlineChanged);
    return id;
  }

  Future<void> addPayment(DebtPayment payment, {required String currencySymbol}) async {
    if (payment.amount <= 0) throw ArgumentError('Payment must be more than zero');
    await _repo.addPayment(payment);
    final status = await _repo.statusById(payment.debtId);
    if (status != null && status.remaining == 0 && !status.debt.isPaid) {
      await _repo.setPaid(payment.debtId, true);
    }
    await _sync(payment.debtId, currencySymbol, allowImmediate: false);
  }

  Future<void> deletePayment(DebtPayment payment, {required String currencySymbol}) async {
    await _repo.deletePayment(payment.id!);
    final status = await _repo.statusById(payment.debtId);
    // Undo an automatic "paid" if the balance is open again.
    if (status != null && status.debt.isPaid && status.remaining > 0) {
      await _repo.setPaid(payment.debtId, false);
    }
    await _sync(payment.debtId, currencySymbol, allowImmediate: false);
  }

  Future<void> setPaid(int debtId, bool paid, {required String currencySymbol}) async {
    await _repo.setPaid(debtId, paid);
    await _sync(debtId, currencySymbol, allowImmediate: false);
  }

  /// Whether deleting should ask about a linked expense.
  Future<bool> hasLinkedExpense(int debtId) async => await _repo.linkedExpense(debtId) != null;

  Future<void> delete(int debtId, {bool removeLinkedExpense = false}) async {
    await _cancel(debtId);
    await _repo.delete(debtId, removeLinkedExpense: removeLinkedExpense);
  }

  /// Re-creates reminders for every open debt (app start, after a restore).
  /// Never fires one "right away" here, so opening the app doesn't repeat
  /// a reminder that was already shown.
  Future<void> rescheduleAll({required String currencySymbol}) async {
    for (final s in await _repo.allStatuses()) {
      await _schedule(s, currencySymbol, allowImmediate: false);
    }
  }

  Future<void> _sync(int debtId, String symbol, {required bool allowImmediate}) async {
    final status = await _repo.statusById(debtId);
    if (status == null) return;
    await _schedule(status, symbol, allowImmediate: allowImmediate);
  }

  /// Reminders are a nice-to-have: a scheduling error must not make a save
  /// that already reached the database look like it failed.
  Future<void> _schedule(DebtStatus status, String symbol, {required bool allowImmediate}) async {
    final debt = status.debt;
    final id = debt.id;
    if (id == null) return;
    try {
      final deadline = debt.dueDate;
      final at = (status.isSettled || deadline == null)
          ? null
          : DebtReminders.scheduleTime(deadline, _clock(), allowImmediate: allowImmediate);
      if (at == null) {
        // Paid, no deadline, or deadline passed: nothing should fire.
        await _notifications.cancelDebtReminders(id);
        return;
      }
      final text = DebtReminders.message(
        name: debt.creditor,
        amountText: Money.format(status.remaining, symbol: symbol),
        deadline: deadline!,
        at: at,
      );
      await _notifications.scheduleDebtReminder(debtId: id, at: at, title: text.title, body: text.body);
    } catch (e) {
      debugPrint('Could not schedule debt reminder: $e');
    }
  }

  Future<void> _cancel(int debtId) async {
    try {
      await _notifications.cancelDebtReminders(debtId);
    } catch (e) {
      debugPrint('Could not cancel debt reminder: $e');
    }
  }
}
