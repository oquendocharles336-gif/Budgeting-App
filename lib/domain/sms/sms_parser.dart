import '../../core/money.dart';
import '../../data/models/sms_pattern.dart';
import '../../data/models/transaction_entry.dart';

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
}

/// Reads bank/card SMS alerts with user-configurable regex patterns.
///
/// Everything happens on the device; messages are never sent anywhere.
class SmsParser {
  SmsParser(List<SmsPattern> patterns) {
    for (final p in patterns.where((p) => p.enabled)) {
      try {
        final body = RegExp(p.bodyPattern, caseSensitive: false);
        final sender = p.senderPattern.trim().isEmpty
            ? null
            : RegExp(p.senderPattern, caseSensitive: false);
        _compiled.add(_CompiledPattern(p, body, sender));
      } on FormatException catch (e) {
        invalidPatterns[p.bankName] = e.message;
      }
    }
  }

  final _compiled = <_CompiledPattern>[];

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

  /// Returns the first pattern match, or null when nothing matches.
  ParsedSms? parse(SmsMessage message) {
    final body = message.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty || _otp.hasMatch(body)) return null;

    for (final c in _compiled) {
      if (c.sender != null && !c.sender!.hasMatch(message.address)) continue;
      final m = c.body.firstMatch(body);
      if (m == null) continue;

      final amountText = _group(m, 'amount');
      if (amountText == null) continue;
      final amount = Money.parse(amountText);
      if (amount == null || amount == 0) continue;

      final merchant = _group(m, 'merchant')?.trim();
      return ParsedSms(
        message: message,
        pattern: c.pattern,
        amount: amount.abs(),
        merchant: (merchant == null || merchant.isEmpty) ? c.pattern.bankName : merchant,
        kind: c.pattern.kind,
        last4: _group(m, 'last4'),
        reference: _group(m, 'ref'),
      );
    }
    return null;
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
