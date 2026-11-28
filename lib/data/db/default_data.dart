import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/category.dart';
import '../models/sms_pattern.dart';
import '../models/transaction_entry.dart';

/// Data inserted on first install by the migrations.
class DefaultData {
  DefaultData._();

  static const food = 1;
  static const transport = 2;
  static const utilities = 3;
  static const shopping = 4;
  static const health = 5;
  static const entertainment = 6;
  static const education = 7;
  static const other = 8;

  static const categories = <Category>[
    Category(id: food, name: 'Food', icon: 'food', color: 0xFFFF7043, isDefault: true, sortOrder: 0),
    Category(id: transport, name: 'Transport', icon: 'transport', color: 0xFF42A5F5, isDefault: true, sortOrder: 1),
    Category(id: utilities, name: 'Bills', icon: 'bills', color: 0xFFAB47BC, isDefault: true, sortOrder: 2),
    Category(id: shopping, name: 'Shopping', icon: 'shopping', color: 0xFFEC407A, isDefault: true, sortOrder: 3),
    Category(id: health, name: 'Health', icon: 'health', color: 0xFF26A69A, isDefault: true, sortOrder: 4),
    Category(id: entertainment, name: 'Entertainment', icon: 'entertainment', color: 0xFFFFB300, isDefault: true, sortOrder: 5),
    Category(id: education, name: 'Education', icon: 'education', color: 0xFF5C6BC0, isDefault: true, sortOrder: 6),
    Category(id: other, name: 'Other', icon: 'other', color: 0xFF78909C, isDefault: true, sortOrder: 7, role: CategoryRole.other),
  ];

  static const incomeCategories = <Category>[
    Category(name: 'Salary', icon: 'salary', color: 0xFF66BB6A, isDefault: true, sortOrder: 100, kind: TransactionKind.income),
    Category(name: 'Allowance', icon: 'savings', color: 0xFF29B6F6, isDefault: true, sortOrder: 101, kind: TransactionKind.income),
    Category(
      name: 'Borrowed money',
      icon: 'handshake',
      color: 0xFFFFA726,
      isDefault: true,
      sortOrder: 102,
      kind: TransactionKind.income,
      role: CategoryRole.loan,
    ),
    Category(name: 'Paid back to me', icon: 'payback', color: 0xFF26A69A, isDefault: true, sortOrder: 103, kind: TransactionKind.income),
    Category(name: 'Business / sales', icon: 'store', color: 0xFF7E57C2, isDefault: true, sortOrder: 104, kind: TransactionKind.income),
    Category(name: 'Gift received', icon: 'gift', color: 0xFFEC407A, isDefault: true, sortOrder: 105, kind: TransactionKind.income),
    Category(
      name: 'Other income',
      icon: 'other',
      color: 0xFF78909C,
      isDefault: true,
      sortOrder: 106,
      kind: TransactionKind.income,
      role: CategoryRole.other,
    ),
  ];

  static const savingsCategory = Category(
    name: 'Savings',
    icon: 'savings',
    color: 0xFF2E7D32,
    isDefault: true,
    sortOrder: 107,
    kind: TransactionKind.savings,
  );

  static Future<void> ensureIncomeCategories(DatabaseExecutor db) async {
    final existing = await db.rawQuery("SELECT COUNT(*) AS c FROM categories WHERE kind = 'income'");
    if (((existing.first['c'] as int?) ?? 0) > 0) return;
    for (final c in incomeCategories) {
      var name = c.name;
      final clash = await db.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
      if (clash.isNotEmpty) name = '$name (income)';
      await db.insert('categories', (c.copyWith(name: name).toMap())..remove('id'));
    }
  }

  static Future<void> ensureSavingsCategory(DatabaseExecutor db) async {
    final existing = await db.rawQuery("SELECT COUNT(*) AS c FROM categories WHERE kind = 'savings'");
    if (((existing.first['c'] as int?) ?? 0) > 0) return;
    var name = savingsCategory.name;
    final clash = await db.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
    if (clash.isNotEmpty) name = '$name (savings)';
    await db.insert('categories', (savingsCategory.copyWith(name: name).toMap())..remove('id'));
  }

  static const debtCategory = Category(
    name: 'Debt',
    icon: 'handshake',
    color: 0xFF8D6E63,
    isDefault: true,
    sortOrder: 8,
    role: CategoryRole.debt,
  );

  static const feesCategory = Category(
    name: 'Fees',
    icon: 'fees',
    color: 0xFF78909C,
    isDefault: true,
    sortOrder: 9,
    role: CategoryRole.fees,
  );

  static const loanCategory = Category(
    name: 'Loan',
    icon: 'loan',
    color: 0xFF8D6E63,
    isDefault: true,
    sortOrder: 10,
    role: CategoryRole.loanRecord,
  );

  static const salesCategory = Category(
    name: 'Business / sales',
    icon: 'store',
    color: 0xFF7E57C2,
    isDefault: true,
    sortOrder: 104,
    kind: TransactionKind.income,
    role: CategoryRole.sales,
  );

  static Future<int> ensureRoleCategory(DatabaseExecutor db, Category c) async {
    final role = c.role!.name;
    final kind = c.isIncome ? 'income' : 'expense';
    final tagged = await db.query('categories', columns: ['id'], where: 'role = ?', whereArgs: [role], limit: 1);
    if (tagged.isNotEmpty) return tagged.first['id'] as int;
    final named = await db.query(
      'categories',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE AND kind = ? AND role IS NULL',
      whereArgs: [c.name, kind],
      limit: 1,
    );
    if (named.isNotEmpty) {
      final id = named.first['id'] as int;
      await db.update('categories', {'role': role}, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    var name = c.name;
    final clash = await db.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
    if (clash.isNotEmpty) name = '${c.name} ($kind)';
    return db.insert('categories', c.copyWith(name: name).toMap()..remove('id'));
  }

  static Future<int> ensureFeesCategory(DatabaseExecutor db) => ensureRoleCategory(db, feesCategory);
  static Future<int> ensureLoanCategory(DatabaseExecutor db) => ensureRoleCategory(db, loanCategory);
  static Future<int> ensureSalesCategory(DatabaseExecutor db) => ensureRoleCategory(db, salesCategory);

  static Future<int> ensureDebtCategory(DatabaseExecutor db) async {
    final tagged = await db.query('categories', columns: ['id'], where: "role = 'debt'", limit: 1);
    if (tagged.isNotEmpty) return tagged.first['id'] as int;
    return ensureRoleCategory(db, debtCategory);
  }

  static const water = Category(name: 'Water', icon: 'water', color: 0xFF0288D1, isDefault: true, sortOrder: 20);
  static const electricity = Category(name: 'Electricity', icon: 'bolt', color: 0xFFF57C00, isDefault: true, sortOrder: 21);
  static const wifi = Category(name: 'WiFi', icon: 'wifi', color: 0xFF7B1FA2, isDefault: true, sortOrder: 22);
  static const utilitiesCategory = Category(id: utilities, name: 'Utilities', icon: 'utilities', color: 0xFFAB47BC, isDefault: true, sortOrder: 5);

  static const utilityKeywords = <String, List<String>>{
    'Water': ['maynilad', 'manila water', 'primewater', 'water district', 'water bill'],
    'Electricity': ['meralco', 'veco', 'davao light', 'electricity', 'electric bill'],
    'WiFi': ['pldt', 'converge', 'sky cable', 'skyfiber', 'globe at home', 'wifi', 'internet bill'],
    'Utilities': ['globe', 'smart', 'dito', 'rent', 'insurance', 'lpg', 'gasul', 'association dues', 'condo dues'],
  };

  static Future<void> ensureUtilityCategories(DatabaseExecutor db) async {
    await db.update('categories', {'name': 'Utilities', 'icon': 'utilities'}, where: 'id = ?', whereArgs: [utilities]);
    for (final c in [water, electricity, wifi]) {
      final clash = await db.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [c.name], limit: 1);
      if (clash.isEmpty) {
        await db.insert('categories', c.toMap()..remove('id'));
      }
    }
  }

  static Future<void> ensureV7Categories(DatabaseExecutor db) async {
    await ensureIncomeCategories(db);
    await ensureDebtCategory(db);
    await ensureSavingsCategory(db);
    await ensureFeesCategory(db);
    await ensureLoanCategory(db);
    await ensureSalesCategory(db);
  }

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
    utilities: [
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
            CategoryRule(keyword: kw, categoryId: entry.key, priority: 0),
      ];

  static const _amt = r'(?<amount>\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+(?:\.\d{2})?)';
  static const _cur = r'(?:PHP|Php|P|₱)\s?';
  static const _end = r'(?=\s+on\s|\s+via\s|\.\s|\.$|,|;|$)';
  static const _ref = r'(?:.*?Ref(?:\.|erence)?\s*(?:No\.?)?\s*:?\s*(?<ref>[A-Za-z0-9]+))?';

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

  static const notificationPatterns = <SmsPattern>[
    SmsPattern(
      bankName: 'Wallet app: "payment of PHP 100 to MERCHANT"',
      bodyPattern: r'payment\s+of\s+' '$_cur$_amt' r'\s+(?:to|at|for)\s+(?<merchant>.+?)(?:\s+(?:was|has\s+been|is)\s+(?:successful|completed|sent))?' '$_end$_ref',
    ),
    SmsPattern(
      bankName: 'Wallet app: "PHP 100 paid to MERCHANT"',
      bodyPattern: '$_cur$_amt' r'\s+(?:was\s+|has\s+been\s+)?(?:paid|sent|transferred)\s+to\s+(?<merchant>.+?)' '$_end$_ref',
    ),
    SmsPattern(
      bankName: 'Wallet app: "You received PHP 100" (no sender name)',
      bodyPattern: r'(?:received|cash\s*in(?:\s+of)?)\s+' '$_cur$_amt' r'(?!\s+from)' '$_end$_ref',
      kind: TransactionKind.income,
    ),
  ];

  static Future<void> ensureNotificationPatterns(DatabaseExecutor db) async {
    for (final p in notificationPatterns) {
      final same = await db.query('sms_patterns', where: 'bank_name = ?', whereArgs: [p.bankName], limit: 1);
      if (same.isEmpty) await db.insert('sms_patterns', p.toMap());
    }
  }
}
