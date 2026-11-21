/// How to read ambiguous numeric dates like 03/04/2026.
enum DateOrder {
  auto('Auto-detect'),
  ymd('YYYY-MM-DD'),
  mdy('MM/DD/YYYY'),
  dmy('DD/MM/YYYY');

  const DateOrder(this.label);
  final String label;
}

/// Parses the date formats commonly found in bank/card statements:
///   2026-11-20, 2026/11/20, 11/20/2026, 20/11/2026, 11-20-26,
///   Nov 20, 2026, 20 Nov 2026, 20-Nov-26, November 20 2026
/// Any time part after the date is ignored.
class DateParser {
  DateParser._();

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static final _iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})');
  static final _numeric = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');
  static final _dayMonthName = RegExp(r'^(\d{1,2})[\s\-]+([A-Za-z]{3,9})\.?[\s\-,]+(\d{2,4})\b');
  static final _monthNameDay = RegExp(r'^([A-Za-z]{3,9})\.?[\s\-]+(\d{1,2})(?:st|nd|rd|th)?,?[\s\-]+(\d{2,4})\b');

  static DateTime? parse(String input, {DateOrder order = DateOrder.auto}) {
    final s = input.trim();
    if (s.isEmpty) return null;

    var m = _iso.firstMatch(s);
    if (m != null) {
      return _build(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }

    m = _numeric.firstMatch(s);
    if (m != null) {
      final a = int.parse(m[1]!);
      final b = int.parse(m[2]!);
      final year = _year(m[3]!);
      switch (order) {
        case DateOrder.dmy:
          return _build(year, b, a);
        case DateOrder.mdy:
        case DateOrder.ymd:
          return _build(year, a, b);
        case DateOrder.auto:
          // If the first number can't be a month, it must be the day.
          if (a > 12) return _build(year, b, a);
          return _build(year, a, b);
      }
    }

    m = _dayMonthName.firstMatch(s);
    if (m != null) {
      final month = _monthFromName(m[2]!);
      if (month != null) return _build(_year(m[3]!), month, int.parse(m[1]!));
    }

    m = _monthNameDay.firstMatch(s);
    if (m != null) {
      final month = _monthFromName(m[1]!);
      if (month != null) return _build(_year(m[3]!), month, int.parse(m[2]!));
    }
    return null;
  }

  static int? _monthFromName(String name) {
    if (name.length < 3) return null;
    return _months[name.substring(0, 3).toLowerCase()];
  }

  static int _year(String y) {
    final v = int.parse(y);
    if (y.length == 2) return 2000 + v;
    return v;
  }

  static DateTime? _build(int year, int month, int day) {
    if (year < 1900 || year > 2200) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1) return null;
    final lastDay = DateTime(year, month + 1, 0).day;
    if (day > lastDay) return null;
    return DateTime(year, month, day);
  }
}
