import '../models/category.dart';
import '../models/sms_pattern.dart';
import '../models/transaction_entry.dart';

/// Data inserted on first install by the migrations.
class DefaultData {
  DefaultData._();

  // Fixed IDs so the default rules can point at them.
  static const food = 1;
  static const transport = 2;
  static const bills = 3;
  static const shopping = 4;
  static const health = 5;
  static const entertainment = 6;
  static const education = 7;
  static const other = 8;

  static const categories = <Category>[
    Category(id: food, name: 'Food', icon: 'food', color: 0xFFFF7043, isDefault: true, sortOrder: 0),
    Category(id: transport, name: 'Transport', icon: 'transport', color: 0xFF42A5F5, isDefault: true, sortOrder: 1),
    Category(id: bills, name: 'Bills', icon: 'bills', color: 0xFFAB47BC, isDefault: true, sortOrder: 2),
    Category(id: shopping, name: 'Shopping', icon: 'shopping', color: 0xFFEC407A, isDefault: true, sortOrder: 3),
    Category(id: health, name: 'Health', icon: 'health', color: 0xFF26A69A, isDefault: true, sortOrder: 4),
    Category(id: entertainment, name: 'Entertainment', icon: 'entertainment', color: 0xFFFFB300, isDefault: true, sortOrder: 5),
    Category(id: education, name: 'Education', icon: 'education', color: 0xFF5C6BC0, isDefault: true, sortOrder: 6),
    Category(id: other, name: 'Other', icon: 'other', color: 0xFF78909C, isDefault: true, sortOrder: 7),
  ];

  static const _keywords = <int, List<String>>{
    food: [
      'jollibee', 'mcdonald', 'mang inasal', 'chowking', 'greenwich', 'kfc',
      'starbucks', 'grabfood', 'grab food', 'foodpanda', 'restaurant', 'cafe',
      'bakery', 'puregold', 'savemore', 'robinsons supermarket', 'sm supermarket',
      '7 eleven', 'ministop', 'family mart',
    ],
    transport: [
      'grab', 'angkas', 'joyride', 'lrt', 'mrt', 'beep', 'petron', 'shell',
      'caltex', 'seaoil', 'autosweep', 'easytrip', 'parking', 'taxi', 'jeep',
    ],
    bills: [
      'meralco', 'maynilad', 'manila water', 'pldt', 'globe', 'smart', 'converge',
      'sky cable', 'dito', 'rent', 'insurance',
    ],
    shopping: ['lazada', 'shopee', 'zalora', 'uniqlo', 'sm store', 'ace hardware', 'temu'],
    health: ['mercury drug', 'watsons', 'southstar', 'hospital', 'clinic', 'pharmacy', 'dental'],
    entertainment: ['netflix', 'spotify', 'youtube', 'disney', 'cinema', 'steam', 'playstation', 'viu'],
    education: ['tuition', 'national bookstore', 'fully booked', 'coursera', 'udemy', 'school'],
  };

  static List<CategoryRule> get rules => [
        for (final entry in _keywords.entries)
          for (final kw in entry.value)
            // Ties are broken by keyword length in AutoCategorizer, so
            // "grabfood" (Food) beats "grab" (Transport).
            CategoryRule(keyword: kw, categoryId: entry.key, priority: 0),
      ];

  // Regex building blocks. Tested against sample alerts in
  // test/domain/sms_parser_test.dart.
  static const _amt = r'(?<amount>\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)';
  static const _cur = r'(?:PHP|Php|P|₱)\s?';
  static const _end = r'(?=\s+on\s|\s+via\s|\.\s|\.$|,|;|$)';
  static const _ref = r'(?:.*?Ref(?:\.|erence)?\s*(?:No\.?)?\s*:?\s*(?<ref>[A-Za-z0-9]+))?';

  /// Generic starting patterns. Every bank words its alerts differently, so
  /// users are expected to adjust these in Settings > SMS patterns.
  static const smsPatterns = <SmsPattern>[
    SmsPattern(
      bankName: 'Generic card: "card ending 1234 ... PHP 100 at MERCHANT"',
      bodyPattern: r'(?:ending(?:\s+in)?|x{2,}|\*{2,})\s*(?<last4>\d{4})\b.*?' '$_cur$_amt' r'\s+at\s+(?<merchant>.+?)' '$_end',
    ),
    SmsPattern(
      bankName: 'Generic card: "PHP 100 charged to card xxxx1234 at MERCHANT"',
      bodyPattern: '$_cur$_amt' r'\s.*?(?:card|acct|account)\D{0,20}?(?<last4>\d{4})\b.*?\bat\s+(?<merchant>.+?)' '$_end',
    ),
    SmsPattern(
      bankName: 'E-wallet payment: "paid PHP 100 to MERCHANT"',
      bodyPattern: r'(?:paid|sent)\s+' '$_cur$_amt' r'\s+to\s+(?<merchant>.+?)' '$_end$_ref',
    ),
    SmsPattern(
      bankName: 'E-wallet received: "received PHP 100 from NAME"',
      bodyPattern: r'received\s+' '$_cur$_amt' r'\s+from\s+(?<merchant>.+?)' '$_end$_ref',
      kind: TransactionKind.income,
    ),
  ];
}
