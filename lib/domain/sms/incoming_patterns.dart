import '../../data/models/sms_pattern.dart';
import '../../data/models/transaction_entry.dart';

/// Which way the money in an alert moved, from its wording.
enum MoneyDirection { incoming, outgoing }

/// Built-in rules for money RECEIVED (incoming transfers, credits, cash
/// in), in the wordings Philippine banks and e-wallets use in SMS and app
/// notifications.
///
/// The user's own patterns always run first. These are a fallback, so a
/// "You have received PHP 500.00 of GCash from JUAN" or "Your account
/// ending 1234 has been credited with PHP 5,000.00" is never dropped just
/// because the user's list only has the older "received PHP x from NAME"
/// wording.
class IncomingPatterns {
  IncomingPatterns._();

  // Same building blocks as DefaultData's patterns. The currency must not
  // be glued to a word before it ("top 5", "group 2"): (?<![A-Za-z]).
  static const _amt = r'(?<amount>\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)';
  static const _cur = r'(?<![A-Za-z])(?:PHP|Php|P|₱)\s?';
  static const _end = r'(?=\s+on\s|\s+via\s|\s+at\s|\s+thru\s|\s+through\s|\.\s|\.$|,|;|!|$)';
  static const _ref = r'(?:.*?Ref(?:\.|erence)?\s*(?:No\.?)?\s*:?\s*(?<ref>[A-Za-z0-9]+))?';
  static const _acct = r'(?:account|acct\.?|a/c|card|savings|wallet)\D{0,25}?(?<last4>\d{4})\b';

  /// The description when a built-in rule finds no sender name.
  static const defaultDescription = 'Money received';

  static const patterns = <SmsPattern>[
    // "You have received PHP 500.00 of GCash from JUAN D."
    // "You received a transfer of PHP 1,000.00 via InstaPay from ANA"
    SmsPattern(
      bankName: 'Money received: "received ... PHP 100 ... from NAME"',
      bodyPattern: r'\b(?:received|got)\b.{0,40}?' '$_cur$_amt' r'.{0,60}?\bfrom\s+(?<merchant>.+?)' '$_end$_ref',
      kind: TransactionKind.income,
    ),
    // "JUAN DELA CRUZ sent you PHP 500.00"
    SmsPattern(
      bankName: 'Money received: "NAME sent you PHP 100"',
      bodyPattern: r'(?:^|[!:]\s+|\.\s+)(?<merchant>(?:[^!:.]|(?<=\b\w)\.){2,40}?)\s+(?:has\s+)?(?:sent|transferred)\s+you\s+' '$_cur$_amt' '$_ref',
      kind: TransactionKind.income,
    ),
    // "Your account ending 1234 has been credited with PHP 5,000.00"
    SmsPattern(
      bankName: 'Credit alert: "account 1234 credited with PHP 100"',
      bodyPattern: '$_acct' r'.{0,60}?\b(?:credited|deposited)\b.{0,30}?' '$_cur$_amt' '$_ref',
      kind: TransactionKind.income,
    ),
    // "PHP 5,000.00 has been credited to your account ending 1234"
    SmsPattern(
      bankName: 'Credit alert: "PHP 100 credited to account 1234"',
      bodyPattern: '$_cur$_amt' r'.{0,60}?\b(?:credited|deposited|added|received)\s+(?:to|into|in)\b'
          r'(?:.{0,30}?' '$_acct' r')?' '$_ref',
      kind: TransactionKind.income,
    ),
    // "Cash In of PHP 500.00 ...", "Incoming transfer PHP 200 from ANA",
    // "Refund of PHP 99.00", "Deposit of PHP 1,000"
    SmsPattern(
      bankName: 'Money received: "cash in / incoming transfer / refund PHP 100"',
      bodyPattern: r'\b(?:cash[\s-]?in|incoming(?:\s+(?:fund\s+)?transfer)?|refund(?:ed)?|deposit|credited)\b.{0,30}?'
          '$_cur$_amt' r'(?:.{0,40}?\bfrom\s+(?<merchant>.+?)' '$_end' r')?' '$_ref',
      kind: TransactionKind.income,
    ),
    // Last resorts: "You received PHP 100", "PHP 100 received".
    SmsPattern(
      bankName: 'Money received',
      bodyPattern: r'\breceived\b.{0,40}?' '$_cur$_amt' '$_ref',
      kind: TransactionKind.income,
    ),
    SmsPattern(
      bankName: 'Money received: "PHP 100 received"',
      bodyPattern: '$_cur$_amt' r'\s+(?:was\s+|has\s+been\s+)?received\b' '$_ref',
      kind: TransactionKind.income,
    ),
  ];

  /// Phrases that mean the money came IN. Checked before the outgoing
  /// words, so "sent you" isn't read as "sent".
  static final _incoming = RegExp(
    r'\b(?:received|receive|got|credited|credit(?:ed)?\s+to|cash[\s-]?in|incoming|deposited|deposit\s+of|refund(?:ed)?|'
    r'sent\s+you|(?:sent|transferred)\s+to\s+you(?:r)?(?:\s+(?:account|acct|wallet|savings))?|added\s+to\s+your|has\s+been\s+added)\b',
    caseSensitive: false,
  );

  /// Phrases that mean the money went OUT.
  static final _outgoing = RegExp(
    r'\b(?:paid|pay(?:ment)?|purchase[ds]?|spent|charged|debited|deducted|withdrawn|withdrawal|cash[\s-]?out|'
    r'sent|transferred|used\s+for|bought)\b',
    caseSensitive: false,
  );

  /// The direction the earliest money word points to, or null when the
  /// text has none. "You have received a payment of PHP 500" is incoming
  /// ("received" comes first); "Your payment of PHP 500 to MERALCO was
  /// received" is outgoing ("payment" comes first).
  static MoneyDirection? directionOf(String body) {
    final inc = _incoming.firstMatch(body);
    // "sent you" / "transferred to you" are incoming; blank them out so
    // the "sent" inside them isn't also counted as outgoing.
    final out = _outgoing.firstMatch(_maskIncoming(body));
    if (inc == null && out == null) return null;
    if (out == null) return MoneyDirection.incoming;
    if (inc == null) return MoneyDirection.outgoing;
    return inc.start <= out.start ? MoneyDirection.incoming : MoneyDirection.outgoing;
  }

  /// True when the text has only incoming money words (no outgoing ones).
  static bool clearlyIncoming(String body) =>
      directionOf(body) == MoneyDirection.incoming && _outgoing.firstMatch(_maskIncoming(body)) == null;

  /// True when the text has only outgoing money words.
  static bool clearlyOutgoing(String body) => directionOf(body) == MoneyDirection.outgoing && _incoming.firstMatch(body) == null;

  static final _sentYou = RegExp(
    r'\b(?:sent\s+you|transferred\s+to\s+you\b|(?:sent|transferred)\s+to\s+your\s+(?:account|acct|wallet|savings))\b',
    caseSensitive: false,
  );

  static String _maskIncoming(String body) => body.replaceAllMapped(_sentYou, (m) => ' ' * m[0]!.length);
}
