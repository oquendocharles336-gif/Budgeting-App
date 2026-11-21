import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'debt_service.dart';

/// Local notifications only. Nothing is sent to a server.
class NotificationService implements DebtReminderScheduler {
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

  /// Reminders from a removed feature used ids from here up. Cancelled at
  /// start-up so none fires after updating.
  static const _retiredIdsFrom = 10000000;

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

  /// Shows the debt reminder at [at] (local time), replacing any earlier
  /// one for this debt. A time that is now (or past) shows it right away.
  /// Scheduled reminders are kept by the plugin across app restarts, and
  /// its boot receiver (AndroidManifest) restores them after a reboot.
  @override
  Future<void> scheduleDebtReminder({
    required int debtId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await cancelDebtReminders(debtId);
    await init();
    if (!_ready) return;
    const details = NotificationDetails(android: _debtChannel, iOS: DarwinNotificationDetails());
    if (at.difference(DateTime.now()) < const Duration(minutes: 1)) {
      await _plugin.show(id: _debtId(debtId, 0), title: title, body: body, notificationDetails: details);
      return;
    }
    await _plugin.zonedSchedule(
      id: _debtId(debtId, 0),
      title: title,
      body: body,
      // tz.local is UTC unless changed; converting the instant keeps the
      // exact moment, so the reminder still fires at 9:00 local time.
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details,
      // Inexact = no special "exact alarm" permission needed.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelDebtReminders(int debtId) async {
    await init();
    if (!_ready) return;
    // Slot 1 was the old "due today" reminder; cleared for upgrades.
    await _plugin.cancel(id: _debtId(debtId, 0));
    await _plugin.cancel(id: _debtId(debtId, 1));
  }

  /// Cancels reminders still scheduled by a feature this version removed
  /// (ids from [_retiredIdsFrom]). Safe to call on every start.
  Future<void> cancelRetiredReminders() async {
    await init();
    if (!_ready) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _retiredIdsFrom) await _plugin.cancel(id: p.id);
    }
  }

  Future<void> cancelAll() async {
    await init();
    if (!_ready) return;
    await _plugin.cancelAll();
  }
}
