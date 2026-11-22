import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Things Pitaka can ask the phone to allow.
enum PhoneAccess {
  /// Budget alerts and debt reminders (Android 13+ asks; older phones can
  /// turn them off in settings).
  notifications,

  /// Reading bank texts for "Import from SMS" (optional).
  sms,

  /// "Install unknown apps", needed to install updates from inside the app.
  installUpdates,
}

/// What is allowed right now.
class PhoneAccessStatus {
  const PhoneAccessStatus({required this.notifications, required this.sms, required this.installUpdates});

  /// Used where the phone can't be asked (tests, other platforms): nothing
  /// is shown as missing.
  static const unknown = PhoneAccessStatus(notifications: true, sms: true, installUpdates: true);

  final bool notifications;
  final bool sms;
  final bool installUpdates;

  bool allows(PhoneAccess access) => switch (access) {
        PhoneAccess.notifications => notifications,
        PhoneAccess.sms => sms,
        PhoneAccess.installUpdates => installUpdates,
      };

  @override
  bool operator ==(Object other) =>
      other is PhoneAccessStatus &&
      other.notifications == notifications &&
      other.sms == sms &&
      other.installUpdates == installUpdates;

  @override
  int get hashCode => Object.hash(notifications, sms, installUpdates);
}

/// Talks to the small "pitaka/permissions" handler in MainActivity.java.
/// Android only; elsewhere everything reads as allowed.
class PhoneAccessChannel {
  const PhoneAccessChannel();

  static const _channel = MethodChannel('pitaka/permissions');

  bool get supported => Platform.isAndroid;

  Future<PhoneAccessStatus> status() async {
    if (!supported) return PhoneAccessStatus.unknown;
    try {
      return _parse(await _channel.invokeMapMethod<String, Object?>('status'));
    } on MissingPluginException {
      return PhoneAccessStatus.unknown;
    } on PlatformException catch (e) {
      debugPrint('Permission status failed: ${e.message}');
      return PhoneAccessStatus.unknown;
    }
  }

  /// Opens the phone's settings page for [access] and returns what is
  /// allowed once the user comes back.
  Future<PhoneAccessStatus> openSettings(PhoneAccess access) async {
    if (!supported) return PhoneAccessStatus.unknown;
    final page = switch (access) {
      PhoneAccess.notifications => 'notifications',
      PhoneAccess.installUpdates => 'install',
      PhoneAccess.sms => 'app',
    };
    return _parse(await _channel.invokeMapMethod<String, Object?>('openSettings', {'page': page}));
  }

  static PhoneAccessStatus _parse(Map<String, Object?>? m) {
    if (m == null) return PhoneAccessStatus.unknown;
    return PhoneAccessStatus(
      notifications: m['notifications'] as bool? ?? true,
      sms: m['sms'] as bool? ?? false,
      installUpdates: m['install'] as bool? ?? false,
    );
  }
}
