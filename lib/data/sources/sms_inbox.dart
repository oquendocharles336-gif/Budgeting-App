import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/sms_pattern.dart';

/// Access to the phone's SMS inbox. Android only.
abstract class SmsInbox {
  bool get isSupported;
  Future<bool> hasPermission();

  /// Shows the system permission dialog. Returns true if granted.
  Future<bool> requestPermission();
  Future<List<SmsMessage>> read({DateTime? since, int limit = 500});
}

/// Talks to the small Java handler in MainActivity.java over a
/// MethodChannel. No third-party SMS plugin is used.
class AndroidSmsInbox implements SmsInbox {
  static const _channel = MethodChannel('pitaka/sms');

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  @override
  Future<List<SmsMessage>> read({DateTime? since, int limit = 500}) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('readInbox', {
      'since': since?.millisecondsSinceEpoch ?? 0,
      'limit': limit,
    });
    return [
      for (final m in raw ?? const <Map<Object?, Object?>>[])
        SmsMessage(
          id: '${m['id']}',
          address: (m['address'] as String?) ?? '',
          body: (m['body'] as String?) ?? '',
          date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
        ),
    ];
  }
}
