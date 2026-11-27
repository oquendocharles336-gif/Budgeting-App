import '../../core/money.dart';
import '../../data/models/sms_pattern.dart';
import '../../data/models/transaction_entry.dart';
import 'incoming_patterns.dart';

export 'incoming_patterns.dart' show IncomingPatterns, MoneyDirection;

/// A transaction read out of one SMS alert.
class ParsedSms {
  const ParsedSms({
    required this.message,
    required this.pattern,
    required this.amount,
    required this.merchant,
    required this.kind,
    this.last4,
    this.reference,
  });

  final SmsMessage message;
  final SmsPattern pattern;

  /// Positive centavos.
  final int amount;
  final String merchant;
  final TransactionKind kind;
  final String? last4;
  final String? reference;

  bool get isIncome => kind == TransactionKind.income;

  ParsedSms copyWith({TransactionKind? kind, String? last4, String? reference}) => ParsedSms(
        message: message,
        pattern: pattern,
        amount: amount,
        merchant: merchant,
        kind: kind ?? this.kind,
        last4: last4 ?? this.last4,
        reference: reference ?? this.reference,
      );
}

/// Reads bank/card SMS alerts with user-configurable regex patterns.
///
/// Money received is handled on purpose, not left to pattern order:
///
///  * when an alert's wording says money came in ("received", "credited",
///    "cash in", "sent you") an income pattern is preferred over an
///    expense pattern that happens to match first, and vice versa;
///  * when only a pattern of the wrong kind matches an alert that is
///    clearly one way, the result takes the alert's direction (a credit
///    alert is never saved as spending);
///  * when no user pattern matches a clearly incoming alert, the built-in
///    [IncomingPatterns] are tried, so received money isn't dropped.
///
/// Everything happens on the device; messages are never sent anywhere.
class SmsParser {
  SmsParser(List<SmsPattern> patterns, {bool builtInIncoming = true}) {
    _compileAll(patterns.where((p) => p.enabled), _compiled, report: true);
    if (builtInIncoming) _compileAll(IncomingPatterns.patterns, _fallbacks, report: false);
  }

  void _compileAll(Iterable<SmsPattern> patterns, List<_CompiledPattern> into, {required bool report}) {
    for (final p in patterns) {
      try {
        final body = RegExp(p.bodyPattern, caseSensitive: false);
        final sender = p.senderPattern.trim().isEmpty
            ? null
            : RegExp(p.senderPattern, caseSensitive: false);
        into.add(_CompiledPattern(p, body, sender));
      } on FormatException catch (e) {
        if (report) invalidPatterns[p.bankName] = e.message;
      }
    }
  }

  final _compiled = <_CompiledPattern>[];

  /// Built-in rules for received money, tried after the user's patterns.
  final _fallbacks = <_CompiledPattern>[];

  /// Patterns that failed to compile, by name -> error.
  final invalidPatterns = <String, String>{};

  /// One-time-password messages are never parsed, even when they mention
  /// an amount ("Your OTP for PHP 500 at SHOP is 123456"). Real alerts that
  /// merely say "never share your OTP" are still parsed.
  static final _otp = RegExp(
    r'\b(?:otp|one[\s-]?time[\s-]?(?:password|pin|code)|verification code)\b\W{0,3}'
    r'(?:is\W{0,3}|for\b.{0,60}?\bis\W{0,3})?\d{4,8}\b'
    r'|\b\d{4,8}\W{1,3}is\W{1,3}your\W{1,3}(?:otp|one[\s-]?time|verification)',
    caseSensitive: false,
  );

  /// The best pattern match (see the class comment), or null when nothing
  /// matches.
  ParsedSms? parse(SmsMessage message) {
    final body = message.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty || _otp.hasMatch(body)) return null;

    final direction = IncomingPatterns.directionOf(body);
    final wanted = switch (direction) {
      MoneyDirection.incoming => TransactionKind.income,
      MoneyDirection.outgoing => TransactionKind.expense,
      null => null,
    };

    ParsedSms? first;
    for (final c in _compiled) {
      final p = _try(c, message, body);
      if (p == null) continue;
      // The first match whose kind agrees with the wording wins (a
      // transfer pattern is the user's explicit choice either way).
      if (wanted == null || p.kind == wanted || p.kind == TransactionKind.transfer) return p;
      first ??= p;
    }

    // Received money that no user pattern read (or only an expense
    // pattern did): the built-in rules.
    if (direction == MoneyDirection.incoming) {
      for (final c in _fallbacks) {
        final p = _try(c, message, body, noMerchant: IncomingPatterns.defaultDescription);
        if (p == null) continue;
        // Keep what the user's pattern knew that the built-in one doesn't.
        return first == null ? p : p.copyWith(last4: p.last4 ?? first.last4, reference: p.reference ?? first.reference);
      }
    }

    if (first == null) return null;
    // Only a pattern of the other kind matched. Trust the wording when it
    // is one-sided ("credited", "received" and nothing about paying).
    if (first.kind == TransactionKind.expense && IncomingPatterns.clearlyIncoming(body)) {
      return first.copyWith(kind: TransactionKind.income);
    }
    if (first.kind == TransactionKind.income && IncomingPatterns.clearlyOutgoing(body)) {
      return first.copyWith(kind: TransactionKind.expense);
    }
    return first;
  }

  static ParsedSms? _try(_CompiledPattern c, SmsMessage message, String body, {String? noMerchant}) {
    if (c.sender != null && !c.sender!.hasMatch(message.address)) return null;
    final m = c.body.firstMatch(body);
    if (m == null) return null;
    final amountText = _group(m, 'amount');
    if (amountText == null) return null;
    final amount = Money.parse(amountText);
    if (amount == null || amount == 0) return null;
    final merchant = _group(m, 'merchant')?.trim();
    return ParsedSms(
      message: message,
      pattern: c.pattern,
      amount: amount.abs(),
      merchant: (merchant == null || merchant.isEmpty) ? (noMerchant ?? c.pattern.bankName) : merchant,
      kind: c.pattern.kind,
      last4: _group(m, 'last4'),
      reference: _group(m, 'ref'),
    );
  }

  List<ParsedSms> parseAll(Iterable<SmsMessage> messages) =>
      messages.map(parse).whereType<ParsedSms>().toList();

  /// Validates a user-entered pattern. Returns an error message or null.
  static String? validate(String pattern) {
    if (pattern.trim().isEmpty) return 'Pattern is empty';
    try {
      final r = RegExp(pattern);
      if (!pattern.contains('(?<amount>')) {
        return 'Pattern needs an (?<amount>...) group';
      }
      // Touch the regex so obviously broken patterns fail here.
      r.hasMatch('');
      return null;
    } on FormatException catch (e) {
      return 'Invalid regular expression: ${e.message}';
    }
  }

  static String? _group(RegExpMatch m, String name) {
    if (!m.groupNames.contains(name)) return null;
    final v = m.namedGroup(name);
    return (v == null || v.isEmpty) ? null : v;
  }
}

class _CompiledPattern {
  _CompiledPattern(this.pattern, this.body, this.sender);
  final SmsPattern pattern;
  final RegExp body;
  final RegExp? sender;
}
