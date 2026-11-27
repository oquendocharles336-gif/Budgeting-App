import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/sms_pattern.dart';

/// One payment notification kept by the Android listener
/// (PaymentNotificationListener.java) from a connected app.
class WalletNotification {
  const WalletNotification({
    required this.id,
    required this.packageName,
    required this.title,
    required this.text,
    required this.date,
  });

  /// Stable per notification (app + text + minute), used to skip repeats.
  final String id;
  final String packageName;
  final String title;
  final String text;
  final DateTime date;

  /// Title and text as one message, so the SMS patterns can read it. The
  /// sender is the app's package name.
  String get body {
    final t = title.trim();
    final x = text.trim();
    if (t.isEmpty || x.toLowerCase().contains(t.toLowerCase())) return x;
    final sep = RegExp(r'[.!?:]$').hasMatch(t) ? ' ' : '. ';
    return '$t$sep$x';
  }

  SmsMessage toMessage() => SmsMessage(id: id, address: packageName, body: body, date: date);
}

/// Free, offline e-wallet tracking from app notifications. Android only.
abstract class WalletNotificationSource {
  bool get isSupported;

  /// Whether "Notification access" is on for Pitaka.
  Future<bool> isEnabled();

  /// Which apps' notifications to keep (empty = none, queue cleared).
  Future<void> watch(Set<String> packageNames);

  /// Everything kept since the last call, oldest first. The phone's copy
  /// is deleted.
  Future<List<WalletNotification>> drain();
}

/// Talks to "pitaka/notifications" in MainActivity.java.
class AndroidWalletNotifications implements WalletNotificationSource {
  const AndroidWalletNotifications();

  static const _channel = MethodChannel('pitaka/notifications');

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> watch(Set<String> packageNames) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setWatched', {'packages': packageNames.toList()});
    } on MissingPluginException {
      // Older build without the listener.
    }
  }

  @override
  Future<List<WalletNotification>> drain() async {
    if (!isSupported) return const [];
    final List<Map<Object?, Object?>>? raw;
    try {
      raw = await _channel.invokeListMethod<Map<Object?, Object?>>('drain');
    } on MissingPluginException {
      return const [];
    }
    return [
      for (final m in raw ?? const <Map<Object?, Object?>>[])
        WalletNotification(
          id: '${m['id']}',
          packageName: (m['package'] as String?) ?? '',
          title: (m['title'] as String?) ?? '',
          text: (m['text'] as String?) ?? '',
          date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
        ),
    ];
  }
}
