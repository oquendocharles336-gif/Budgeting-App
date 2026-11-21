import '../../core/money.dart';
import '../../data/models/debt.dart';
import '../../data/repositories/debt_repository.dart';
import 'notification_service.dart';

/// Debt changes + keeping due-date reminders in sync.
class DebtService {
  DebtService({required DebtRepository repository, required this._notifications}) : _repo = repository;

  final DebtRepository _repo;
  final NotificationService _notifications;

  Future<int> save(Debt debt, {required String currencySymbol}) async {
    if (debt.creditor.trim().isEmpty) throw ArgumentError('Creditor is required');
    if (debt.totalAmount <= 0) throw ArgumentError('Total must be more than zero');
    if (debt.initialPaid < 0 || debt.initialPaid > debt.totalAmount) {
      throw ArgumentError('Amount already paid must be between zero and the total');
    }
    final int id;
    if (debt.id == null) {
      id = await _repo.insert(debt);
    } else {
      id = debt.id!;
      await _repo.update(debt);
    }
    await _sync(id, currencySymbol);
    return id;
  }

  Future<void> addPayment(DebtPayment payment, {required String currencySymbol}) async {
    if (payment.amount <= 0) throw ArgumentError('Payment must be more than zero');
    await _repo.addPayment(payment);
    final status = await _repo.statusById(payment.debtId);
    if (status != null && status.remaining == 0 && !status.debt.isPaid) {
      await _repo.setPaid(payment.debtId, true);
    }
    await _sync(payment.debtId, currencySymbol);
  }

  Future<void> deletePayment(DebtPayment payment, {required String currencySymbol}) async {
    await _repo.deletePayment(payment.id!);
    final status = await _repo.statusById(payment.debtId);
    // Undo an automatic "paid" if the balance is open again.
    if (status != null && status.debt.isPaid && status.remaining > 0) {
      await _repo.setPaid(payment.debtId, false);
    }
    await _sync(payment.debtId, currencySymbol);
  }

  Future<void> setPaid(int debtId, bool paid, {required String currencySymbol}) async {
    await _repo.setPaid(debtId, paid);
    await _sync(debtId, currencySymbol);
  }

  Future<void> delete(int debtId) async {
    await _notifications.cancelDebtReminders(debtId);
    await _repo.delete(debtId);
  }

  /// Re-creates reminders for every open debt (after a restore).
  Future<void> rescheduleAll({required String currencySymbol}) async {
    for (final s in await _repo.allStatuses()) {
      await _notifications.scheduleDebtReminders(
        s,
        remainingText: Money.format(s.remaining, symbol: currencySymbol),
      );
    }
  }

  Future<void> _sync(int debtId, String symbol) async {
    final status = await _repo.statusById(debtId);
    if (status == null) return;
    await _notifications.scheduleDebtReminders(status, remainingText: Money.format(status.remaining, symbol: symbol));
  }
}
