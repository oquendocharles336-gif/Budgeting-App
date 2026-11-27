import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/wallet_apps.dart';
import '../../data/models/payment_card.dart';
import '../../data/models/raw_transaction.dart';
import '../../data/models/sms_pattern.dart';
import '../../data/models/transaction_entry.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/sms_pattern_repository.dart';
import '../../data/sources/sms_inbox.dart';
import '../../data/sources/wallet_notifications.dart';
import '../import/transaction_import_service.dart';
import '../sms/sms_parser.dart';

class AutoTrackResult {
  const AutoTrackResult({this.added = 0, this.skipped = 0});
  static const none = AutoTrackResult();

  /// Transactions saved (and taken from / added to their account).
  final int added;

  /// Already recorded (same notification / SMS, or a matching entry).
  final int skipped;
}

/// Free automatic tracking for cards and e-wallets, all on the phone:
///
///  * **App notifications** (Maya, GCash, MariBank, BDO Pay): the Android
///    listener keeps notifications from connected apps; here they are
///    parsed with the SMS patterns and saved to the connected account.
///  * **Bank SMS alerts**: texts that mention a tracked card's last 4
///    digits are saved too (if SMS access is on).
///
/// Each payment is an expense (or income) on the matched account that
/// moves its balance, like a typed entry. Only payments after tracking was
/// turned on count. Repeats are skipped by their notification / SMS id
/// and by the import de-duplicator. Nothing is sent online.
class AutoTrackService {
  AutoTrackService({
    required this._cards,
    required this._patterns,
    required this._importer,
    required this._notifications,
    required this._sms,
    required this._settings,
  });

  final CardRepository _cards;
  final SmsPatternRepository _patterns;
  final TransactionImportService _importer;
  final WalletNotificationSource _notifications;
  final SmsInbox _sms;
  final SettingsRepository _settings;

  bool get supported => _notifications.isSupported;

  Future<bool> notificationAccessOn() => _notifications.isEnabled();

  Future<List<PaymentCard>> _tracked() async => [for (final c in await _cards.all()) if (c.tracksAutomatically) c];

  /// Tells the Android listener which apps to keep notifications from.
  /// Call after a card is connected or disconnected, and at start-up.
  Future<void> syncWatchList() async {
    final apps = {for (final c in await _tracked()) ?c.walletApp?.packageName};
    await _notifications.watch(apps);
  }

  /// Reads what came in since last time and saves it. Never throws: a
  /// problem is logged and the next run tries again.
  Future<AutoTrackResult> run() async {
    if (!supported) return AutoTrackResult.none;
    try {
      final cards = await _tracked();
      await syncWatchList();
      if (cards.isEmpty) return AutoTrackResult.none;
      final parser = SmsParser(await _patterns.all());
      final raws = [
        ...await _fromNotifications(cards, parser),
        ...await _fromSms(cards, parser),
      ];
      if (raws.isEmpty) return AutoTrackResult.none;
      final candidates = await _importer.prepare(raws);
      final result = await _importer.commit(candidates, moveBalances: true);
      return AutoTrackResult(added: result.inserted, skipped: result.skipped);
    } catch (e) {
      debugPrint('Automatic tracking failed: $e');
      return AutoTrackResult.none;
    }
  }

  Future<List<RawTransaction>> _fromNotifications(List<PaymentCard> cards, SmsParser parser) async {
    final out = <RawTransaction>[];
    for (final n in await _notifications.drain()) {
      final app = WalletApp.forPackage(n.packageName);
      if (app == null) continue;
      final linked = [for (final c in cards) if (c.walletApp == app) c];
      if (linked.isEmpty) continue;
      final parsed = parser.parse(n.toMessage());
      if (parsed == null) continue;
      final card = pickCard(linked, parsed.last4);
      if (card == null || n.date.isBefore(card.autoTrackSince!)) continue;
      out.add(RawTransaction(
        date: n.date,
        // A pattern without a merchant group falls back to its own name.
        description: parsed.merchant == parsed.pattern.bankName ? app.label : parsed.merchant,
        amount: parsed.amount,
        kind: parsed.kind,
        source: TransactionSourceType.bankSync,
        cardId: card.id,
        externalId: parsed.reference != null ? 'ref:${parsed.reference}' : 'notif:${n.id}',
        notes: 'Auto-tracked from ${app.label}',
        originalText: n.body,
      ));
    }
    return out;
  }

  /// Bank texts for tracked cards (matched by last 4 digits). Each text is
  /// only read once ([SettingsRepository.autoTrackSmsSeen]).
  Future<List<RawTransaction>> _fromSms(List<PaymentCard> cards, SmsParser parser) async {
    if (!_sms.isSupported || !await _sms.hasPermission()) return const [];
    final earliest = cards.map((c) => c.autoTrackSince!).reduce((a, b) => a.isBefore(b) ? a : b);
    final seen = int.tryParse(await _settings.get(SettingsRepository.autoTrackSmsSeen) ?? '') ?? 0;
    final since = DateTime.fromMillisecondsSinceEpoch(math.max(seen + 1, earliest.millisecondsSinceEpoch));
    final List<SmsMessage> messages;
    try {
      messages = await _sms.read(since: since, limit: 500);
    } catch (e) {
      debugPrint('Automatic tracking could not read SMS: $e');
      return const [];
    }
    if (messages.isEmpty) return const [];
    final newest = messages.map((m) => m.date.millisecondsSinceEpoch).reduce(math.max);
    await _settings.set(SettingsRepository.autoTrackSmsSeen, '$newest');
    final out = <RawTransaction>[];
    for (final p in parser.parseAll(messages)) {
      final last4 = p.last4;
      if (last4 == null) continue;
      final matches = [for (final c in cards) if (c.last4 == last4) c];
      if (matches.length != 1) continue; // unknown or ambiguous card
      final card = matches.single;
      if (p.message.date.isBefore(card.autoTrackSince!)) continue;
      out.add(RawTransaction(
        date: p.message.date,
        description: p.merchant,
        amount: p.amount,
        kind: p.kind,
        source: TransactionSourceType.bankSync,
        cardId: card.id,
        // Same ids as "Import from SMS", so a later manual import skips them.
        externalId: p.reference != null ? 'ref:${p.reference}' : 'sms:${p.message.id}',
        notes: 'Auto-tracked from SMS',
        originalText: p.message.body,
      ));
    }
    return out;
  }

  /// The account a notification belongs to: the one whose last 4 digits
  /// it mentions, else the only one connected to that app, else the oldest.
  static PaymentCard? pickCard(List<PaymentCard> linked, String? last4) {
    if (linked.isEmpty) return null;
    if (last4 != null) {
      for (final c in linked) {
        if (c.last4 == last4) return c;
      }
    }
    final sorted = [...linked]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sorted.first;
  }
}
