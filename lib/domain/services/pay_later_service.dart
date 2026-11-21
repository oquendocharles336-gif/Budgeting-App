import 'package:flutter/foundation.dart';

import '../../core/money.dart';
import '../../data/db/default_data.dart';
import '../../data/models/pay_later.dart';
import '../../data/repositories/pay_later_repository.dart';
import '../debt/debt_reminder.dart';
import '../pay_later/pay_later_rules.dart';
import 'budget_alert_service.dart';

/// What Pay Later needs from the notification plugin (a fake in tests).
abstract interface class PayLaterReminderScheduler {
  Future<void> schedulePayLaterReminder({
    required int itemId,
    required DateTime at,
    required String title,
    required String body,
  });

  Future<void> cancelPayLaterReminder(int itemId);
}

/// Pay Later: a purchase made now and paid later.
///
///  * While unpaid it is only a reminder: not spending, no balance change.
///  * "Paid" creates exactly one expense (amount, category, the account it
///    was paid from, the payment date) and marks the item paid in the same
///    SQLite transaction, so it is counted once. A second "Paid" does nothing.
///  * Undo ("Mark unpaid") deletes that expense again.
///  * Reminders reuse the debt rules: 2 days before the due date at 9:00 AM
///    (with the same fallbacks), rescheduled on change, cancelled when paid
///    or deleted.
class PayLaterService {
  PayLaterService({
    required PayLaterRepository repository,
    required this._notifications,
    this._alerts,
    DateTime Function()? clock,
  })  : _repo = repository,
        _clock = clock ?? DateTime.now;

  final PayLaterRepository _repo;
  final PayLaterReminderScheduler _notifications;
  final BudgetAlertService? _alerts;
  final DateTime Function() _clock;

  /// Adds or edits an item. A new item with an [opKey] is inserted once,
  /// even if the save is retried.
  Future<int> save(PayLaterItem item, {required String currencySymbol, String? opKey}) async {
    if (item.item.trim().isEmpty) throw ArgumentError('Enter what you bought');
    if (item.amount <= 0) throw ArgumentError('Amount must be more than zero');
    final now = _clock();
    final clean = item.copyWith(item: item.item.trim(), updatedAt: now);
    final int id;
    var dueChanged = true;
    if (item.id == null) {
      id = await _repo.insert(clean, opKey: opKey);
    } else {
      id = item.id!;
      final before = await _repo.byId(id);
      dueChanged = before?.dueDate != item.dueDate;
      await _repo.update(clean);
    }
    await _sync(id, currencySymbol, allowImmediate: dueChanged);
    return id;
  }

  /// Marks it paid from [accountId] (null = Cash) and creates its expense.
  /// Returns `alreadyPaid: true` (and creates nothing) if it was paid before.
  Future<MarkPaidResult> markPaid(int id, {required int? accountId, DateTime? paidAt}) async {
    final now = _clock();
    final when = paidAt ?? now;
    final result = await _repo.markPaid(
      id,
      paidAt: when,
      expenseFor: (item) => PayLaterRules.expenseFor(
        item,
        accountId: accountId,
        paidAt: when,
        fallbackCategoryId: DefaultData.other,
        now: now,
      ),
    );
    await _cancel(id);
    if (!result.alreadyPaid) {
      try {
        await _alerts?.checkMonth(when);
      } catch (e) {
        debugPrint('Budget alert check failed: $e');
      }
    }
    return result;
  }

  /// Undo of [markPaid]: removes its expense and brings the reminder back.
  Future<void> markUnpaid(int id, {required String currencySymbol}) async {
    await _repo.markUnpaid(id);
    await _sync(id, currencySymbol, allowImmediate: false);
  }

  Future<void> delete(int id, {bool removeExpense = false}) async {
    await _cancel(id);
    await _repo.delete(id, removeExpense: removeExpense);
  }

  /// Re-creates reminders for every unpaid item (app start, after a restore).
  Future<void> rescheduleAll({required String currencySymbol}) async {
    for (final item in await _repo.all()) {
      await _schedule(item, currencySymbol, allowImmediate: false);
    }
  }

  Future<void> _sync(int id, String symbol, {required bool allowImmediate}) async {
    final item = await _repo.byId(id);
    if (item == null) return;
    await _schedule(item, symbol, allowImmediate: allowImmediate);
  }

  /// A scheduling error never makes a saved change look failed.
  Future<void> _schedule(PayLaterItem item, String symbol, {required bool allowImmediate}) async {
    final id = item.id;
    if (id == null) return;
    try {
      final at = item.isPaid ? null : DebtReminders.scheduleTime(item.dueDate, _clock(), allowImmediate: allowImmediate);
      if (at == null) {
        await _notifications.cancelPayLaterReminder(id);
        return;
      }
      final text = PayLaterRules.reminderText(
        item: item.item,
        amountText: Money.format(item.amount, symbol: symbol),
        due: item.dueDate,
        at: at,
      );
      await _notifications.schedulePayLaterReminder(itemId: id, at: at, title: text.title, body: text.body);
    } catch (e) {
      debugPrint('Could not schedule Pay Later reminder: $e');
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await _notifications.cancelPayLaterReminder(id);
    } catch (e) {
      debugPrint('Could not cancel Pay Later reminder: $e');
    }
  }
}
