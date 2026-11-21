import 'package:intl/intl.dart';

/// All money in the app is stored as an integer number of minor units
/// (centavos for PHP). 1 peso = 100 centavos. This avoids floating point
/// rounding errors like 0.1 + 0.2 != 0.3.
class Money {
  Money._();

  /// Parses text such as "1,234.56", "₱1,234.56", "PHP 99", "-50", "(50.00)"
  /// into signed centavos. Returns null when the text is not a valid amount.
  ///
  /// With [decimalComma] = true the formats are swapped: "1.234,56".
  static int? parse(String input, {bool decimalComma = false}) {
    var s = input.trim();
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1).trim();
    }
    // Trailing minus or "CR"/"DR" markers used by some statements.
    final upper = s.toUpperCase();
    if (upper.endsWith('CR')) {
      negative = true;
      s = s.substring(0, s.length - 2).trim();
    } else if (upper.endsWith('DR')) {
      s = s.substring(0, s.length - 2).trim();
    }
    if (s.endsWith('-')) {
      negative = !negative;
      s = s.substring(0, s.length - 1).trim();
    }
    if (s.startsWith('-')) {
      negative = !negative;
      s = s.substring(1).trim();
    } else if (s.startsWith('+')) {
      s = s.substring(1).trim();
    }
    // Strip currency symbols / codes and spaces.
    s = s.replaceAll(RegExp(r'[A-Za-z₱$€£¥\s]'), '');
    if (s.startsWith('-')) {
      negative = !negative;
      s = s.substring(1);
    }

    final thousands = decimalComma ? '.' : ',';
    final decimal = decimalComma ? ',' : '.';
    s = s.replaceAll(thousands, '');
    if (s.isEmpty) return null;

    final parts = s.split(decimal);
    if (parts.length > 2) return null;
    final whole = parts[0].isEmpty ? '0' : parts[0];
    if (!RegExp(r'^\d+$').hasMatch(whole)) return null;
    var frac = parts.length == 2 ? parts[1] : '';
    if (frac.isNotEmpty && !RegExp(r'^\d+$').hasMatch(frac)) return null;
    if (parts.length == 2 && frac.isEmpty && parts[0].isEmpty) return null;

    // Round half-up to 2 decimal places using integer math only.
    var roundUp = false;
    if (frac.length > 2) {
      roundUp = frac.codeUnitAt(2) >= 0x35; // '5'
      frac = frac.substring(0, 2);
    }
    frac = frac.padRight(2, '0');

    // Guard against absurd values (> 1 trillion) overflowing.
    if (whole.length > 13) return null;
    var value = int.parse(whole) * 100 + int.parse(frac);
    if (roundUp) value += 1;
    return negative ? -value : value;
  }

  /// Formats centavos for display, e.g. 123456 -> "₱1,234.56".
  static String format(int centavos, {String symbol = '₱', bool showPlus = false}) {
    final f = NumberFormat.currency(symbol: symbol, decimalDigits: 2, locale: 'en_US');
    final text = f.format(centavos.abs() / 100);
    if (centavos < 0) return '-$text';
    if (showPlus && centavos > 0) return '+$text';
    return text;
  }

  /// Short form for chart axes: 1500000 -> "₱15K".
  static String compact(int centavos, {String symbol = '₱'}) {
    final f = NumberFormat.compactCurrency(symbol: symbol, decimalDigits: 0, locale: 'en_US');
    return f.format(centavos / 100);
  }

  /// Text for an input field: 123456 -> "1234.56".
  static String toInput(int centavos) {
    final whole = centavos ~/ 100;
    final frac = (centavos % 100).toString().padLeft(2, '0');
    return frac == '00' ? '$whole' : '$whole.$frac';
  }
}

/// Supported display currencies. All use 2 decimal places.
class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.name);
  final String code;
  final String symbol;
  final String name;

  static const all = <CurrencyInfo>[
    CurrencyInfo('PHP', '₱', 'Philippine Peso'),
    CurrencyInfo('USD', r'$', 'US Dollar'),
    CurrencyInfo('EUR', '€', 'Euro'),
    CurrencyInfo('GBP', '£', 'British Pound'),
    CurrencyInfo('SGD', r'S$', 'Singapore Dollar'),
    CurrencyInfo('AUD', r'A$', 'Australian Dollar'),
    CurrencyInfo('CAD', r'C$', 'Canadian Dollar'),
    CurrencyInfo('HKD', r'HK$', 'Hong Kong Dollar'),
    CurrencyInfo('MYR', 'RM', 'Malaysian Ringgit'),
  ];

  static CurrencyInfo byCode(String? code) =>
      all.firstWhere((c) => c.code == code, orElse: () => all.first);
}
