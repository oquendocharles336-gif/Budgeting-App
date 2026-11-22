import '../../data/sources/phone_access.dart';
import '../../data/sources/sms_inbox.dart';
import 'app_lock_service.dart';
import 'notification_service.dart';

export '../../data/sources/phone_access.dart' show PhoneAccess, PhoneAccessStatus;

/// The "Allow" buttons: asks Android for what Pitaka needs.
///
/// First the system's own question (notifications, SMS). If Android won't
/// show it (the user said no before), or the access can only be given in
/// settings ("Install unknown apps"), the phone's settings page for Pitaka
/// opens instead, and the new status is read when the user comes back.
/// The app doesn't lock while the user is on Android's screens.
class PhoneAccessService {
  PhoneAccessService({
    required NotificationService notifications,
    required SmsInbox sms,
    PhoneAccessChannel channel = const PhoneAccessChannel(),
  })  : _notifications = notifications,
        _sms = sms,
        _channel = channel;

  final NotificationService _notifications;
  final SmsInbox _sms;
  final PhoneAccessChannel _channel;

  /// Accesses whose system question was already shown in this run. Android
  /// shows it at most twice; after a "no", the button opens settings.
  static final _askedThisRun = <PhoneAccess>{};

  /// A system question answered faster than this was never on screen
  /// (Android declined by itself): open settings instead.
  static const _noDialogUnder = Duration(milliseconds: 500);

  bool get supported => _channel.supported;

  Future<PhoneAccessStatus> status() => _channel.status();

  /// True when the next [allow] for [access] opens the settings page.
  bool opensSettings(PhoneAccess access) =>
      access == PhoneAccess.installUpdates || _askedThisRun.contains(access);

  /// Asks for [access]. Returns whether it is allowed afterwards.
  Future<bool> allow(PhoneAccess access) => LockGuard.run(() async {
        if (!opensSettings(access)) {
          _askedThisRun.add(access);
          final watch = Stopwatch()..start();
          final granted = switch (access) {
            PhoneAccess.notifications => await _notifications.requestPermission(),
            PhoneAccess.sms => await _sms.requestPermission(),
            PhoneAccess.installUpdates => false,
          };
          final now = await _channel.status();
          if (granted && now.allows(access)) return true;
          // The user saw the question and said no: respect it this time.
          if (watch.elapsed >= _noDialogUnder) return now.allows(access);
        }
        final after = await _channel.openSettings(access);
        return after.allows(access);
      });
}
