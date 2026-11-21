import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/debt.dart';

/// Local notifications only. Nothing is sent to a server.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _budgetChannel = AndroidNotificationDetails(
    'budget_alerts',
    'Budget alerts',
    channelDescription: 'Alerts when you reach 80% and 100% of a budget',
    importance: Importance.high,
    priority: Priority.high,
    // Amounts and names stay hidden on the phone's lock screen.
    visibility: NotificationVisibility.private,
  );

  static const _debtChannel = AndroidNotificationDetails(
    'debt_reminders',
    'Debt reminders',
    channelDescription: 'Reminders before a debt is due',
    importance: Importance.high,
    priority: Priority.high,
    visibility: NotificationVisibility.private,
  );

  /// Budget alerts use ids 1000..; debt reminders use 100000 + debtId * 2.
  static int budgetAlertId(int? categoryId, int threshold) =>
      1000 + (categoryId ?? 0) * 2 + (threshold >= 100 ? 1 : 0);
  static int _debtId(int debtId, int which) => 100000 + debtId * 2 + which;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings: settings);
      _ready = true;
    } catch (e) {
      // Notifications are a nice-to-have; the app works without them
      // (e.g. in widget tests or on unsupported platforms).
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Asks for permission (Android 13+ and iOS). Returns true if allowed.
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    return false;
  }

  Future<void> showBudgetAlert({required int id, required String title, required String body}) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: _budgetChannel,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Schedules two reminders at 9:00 AM: one day before and on the due date.
  /// Existing reminders for the debt are replaced.
  Future<void> scheduleDebtReminders(DebtStatus status, {required String remainingText}) async {
    final debt = status.debt;
    if (debt.id == null) return;
    await cancelDebtReminders(debt.id!);
    if (status.isSettled || debt.dueDate == null) return;
    await init();
    if (!_ready) return;

    final due = debt.dueDate!;
    final now = DateTime.now();
    final reminders = [
      (which: 0, at: DateTime(due.year, due.month, due.day - 1, 9), text: 'due tomorrow'),
      (which: 1, at: DateTime(due.year, due.month, due.day, 9), text: 'due today'),
    ];
    for (final r in reminders) {
      if (!r.at.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: _debtId(debt.id!, r.which),
        title: '${debt.creditor}: payment ${r.text}',
        body: '$remainingText remaining.',
        // tz.local is UTC unless changed; converting the instant keeps the
        // exact moment, so the reminder still fires at 9:00 local time.
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: const NotificationDetails(
          android: _debtChannel,
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact = no special "exact alarm" permission needed.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelDebtReminders(int debtId) async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _debtId(debtId, 0));
    await _plugin.cancel(id: _debtId(debtId, 1));
  }

  Future<void> cancelAll() async {
    await init();
    if (!_ready) return;
    await _plugin.cancelAll();
  }
}
