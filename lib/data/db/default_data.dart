import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/category.dart';
import '../models/sms_pattern.dart';
import '../models/transaction_entry.dart';

/// Data inserted on first install by the migrations.
class DefaultData {
  DefaultData._();

  // Fixed IDs so the default rules can point at them.
  static const food = 1;
  static const transport = 2;

  /// Was "Bills" until 1.6.0. [ensureUtilityCategories] renames it to
  /// "Utilities" (same id, so its transactions and budgets stay) and adds
  /// Water, Electricity and WiFi next to it.
  static const utilities = 3;
  static const shopping = 4;
  static const health = 5;
  static const entertainment = 6;
  static const education = 7;
  static const other = 8;

  /// The v1 install set. Frozen: migration v1 inserts exactly this, and
  /// v12 ([ensureUtilityCategories]) then replaces "Bills". Every place
  /// that puts the defaults back calls [ensureUtilityCategories] after it.
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

  /// Where money comes from. IDs are assigned on insert.
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

  /// Inserts the income categories if there are none (new install, upgrade,
  /// or a backup from before income categories existed). A name already
  /// used by one of the user's own categories gets an "(income)" suffix.
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

  static const debtCategory = Category(
    name: 'Debt',
    icon: 'handshake',
    color: 0xFF8D6E63,
    isDefault: true,
    sortOrder: 8,
    role: CategoryRole.debt,
  );

  /// The expense category new debts are filed under. Reuses a "Debt"
  /// expense category the user already made; returns its id.
  static Future<int> ensureDebtCategory(DatabaseExecutor db) async {
    final tagged = await db.query('categories', columns: ['id'], where: "role = 'debt'", limit: 1);
    if (tagged.isNotEmpty) return tagged.first['id'] as int;
    final named = await db.query(
      'categories',
      columns: ['id'],
      where: "name = ? COLLATE NOCASE AND kind = 'expense' AND role IS NULL",
      whereArgs: [debtCategory.name],
      limit: 1,
    );
    if (named.isNotEmpty) {
      final id = named.first['id'] as int;
      await db.update('categories', {'role': 'debt'}, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    var name = debtCategory.name;
    final clash = await db.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
    if (clash.isNotEmpty) name = 'Debt (expense)';
    return db.insert('categories', debtCategory.copyWith(name: name).toMap()..remove('id'));
  }

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

  /// Finds the category with [role], else tags an untagged one of the same
  /// name and kind the user already has, else creates it. Returns its id.
  /// Same approach as [ensureDebtCategory], so nothing the user made is
  /// duplicated or renamed.
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

  /// Categories added in v7 (also run after a restore and "Delete all").
  static Future<void> ensureV7Categories(DatabaseExecutor db) async {
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
    // v1 "Bills" keywords (frozen). ensureUtilityCategories moves them to
    // Water / Electricity / WiFi / Utilities by [utilityKeywords].
    utilities: [
      'meralco', 'maynilad', 'manila water', 'pldt', 'globe', 'smart', 'converge',
      'sky cable', 'dito', 'rent', 'insurance',
    ],
    shopping: ['lazada', 'shopee', 'zalora', 'uniqlo', 'sm store', 'ace hardware', 'temu'],
    health: ['mercury drug', 'watsons', 'southstar', 'hospital', 'clinic', 'pharmacy', 'dental'],
    entertainment: ['netflix', 'spotify', 'youtube', 'disney', 'cinema', 'steam', 'playstation', 'viu'],
    education: ['tuition', 'national bookstore', 'fully booked', 'coursera', 'udemy', 'school'],
  };

  // ---------------------------------------------------------------------------
  // Utilities (1.6.0): "Bills" -> Water, Electricity, WiFi, Utilities
  // ---------------------------------------------------------------------------

  static const water = Category(name: 'Water', icon: 'water', color: 0xFF29B6F6, isDefault: true, sortOrder: 2);
  static const electricity = Category(name: 'Electricity', icon: 'electricity', color: 0xFFFFA726, isDefault: true, sortOrder: 3);
  static const wifi = Category(name: 'WiFi', icon: 'internet', color: 0xFF26C6DA, isDefault: true, sortOrder: 4);
  static const utilitiesCategory =
      Category(id: utilities, name: 'Utilities', icon: 'utilities', color: 0xFFAB47BC, isDefault: true, sortOrder: 5);

  /// In the order they are shown.
  static const utilityCategories = <Category>[water, electricity, wifi, utilitiesCategory];

  /// Auto-categorization keywords for the utility categories, by category
  /// name. Longest keyword wins, so "globe at home" (WiFi) beats "globe"
  /// (Utilities: mobile load / postpaid).
  static const utilityKeywords = <String, List<String>>{
    'Water': ['maynilad', 'manila water', 'primewater', 'water district', 'water bill'],
    'Electricity': ['meralco', 'veco', 'davao light', 'electricity', 'electric bill'],
    'WiFi': ['pldt', 'converge', 'sky cable', 'skyfiber', 'globe at home', 'wifi', 'internet bill'],
    'Utilities': ['globe', 'smart', 'dito', 'rent', 'insurance', 'lpg', 'gasul', 'association dues', 'condo dues'],
  };

  /// Replaces the old "Bills" category with Water, Electricity, WiFi and
  /// Utilities. Safe to run more than once (migration v12, after a restore
  /// of an older backup, after "Delete all my data").
  ///
  /// * "Bills" is renamed to "Utilities" (same id), so every transaction,
  ///   budget and rule pointing at it keeps working. If "Utilities"
  ///   already exists (e.g. an old backup merged into a new install), the
  ///   Bills transactions, rules and budgets move into it and Bills goes.
  /// * Water / Electricity / WiFi are added; a category the user already
  ///   has with that name is reused instead of duplicated.
  /// * Keyword rules still on Bills/Utilities move to the matching new
  ///   category. Rules the user pointed somewhere else are left alone.
  static Future<void> ensureUtilityCategories(DatabaseExecutor db) async {
    Future<Map<String, Object?>?> named(String name) async {
      final rows = await db.query('categories', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
      return rows.isEmpty ? null : rows.first;
    }

    final bills = await named('Bills');
    var utilitiesRow = await named(utilitiesCategory.name);
    var insertedFirstTime = false;
    int? base; // sort order the four start at
    if (bills != null && (bills['kind'] ?? 'expense') == 'expense') {
      final billsId = bills['id'] as int;
      if (utilitiesRow == null) {
        base = bills['sort_order'] as int? ?? 2;
        await db.update(
          'categories',
          {'name': utilitiesCategory.name, 'icon': utilitiesCategory.icon},
          where: 'id = ?',
          whereArgs: [billsId],
        );
        utilitiesRow = await named(utilitiesCategory.name);
        insertedFirstTime = true;
      } else {
        final utilId = utilitiesRow['id'] as int;
        await db.update('transactions', {'category_id': utilId}, where: 'category_id = ?', whereArgs: [billsId]);
        await db.update('category_rules', {'category_id': utilId}, where: 'category_id = ?', whereArgs: [billsId]);
        // Same month in both: add the Bills amount to the Utilities budget.
        await db.execute('''
          UPDATE budgets SET amount = amount + (
            SELECT b.amount FROM budgets b WHERE b.category_id = ? AND b.month = budgets.month)
          WHERE category_id = ? AND month IN (SELECT month FROM budgets WHERE category_id = ?)''', [billsId, utilId, billsId]);
        await db.execute('''
          UPDATE budgets SET category_id = ?
          WHERE category_id = ? AND month NOT IN (SELECT month FROM budgets WHERE category_id = ?)''', [utilId, billsId, utilId]);
        await db.delete('budgets', where: 'category_id = ?', whereArgs: [billsId]);
        await db.delete('categories', where: 'id = ?', whereArgs: [billsId]);
      }
    }
    if (utilitiesRow == null) {
      // No Bills (renamed or deleted by the user): add Utilities.
      final c = utilitiesCategory.copyWith(sortOrder: await _nextSort(db));
      await db.insert('categories', c.toMap()..remove('id'));
      utilitiesRow = await named(utilitiesCategory.name);
    }
    // Make room right where Bills was, so the four sit together.
    if (insertedFirstTime && base != null) {
      await db.execute(
        "UPDATE categories SET sort_order = sort_order + 3 WHERE kind = 'expense' AND sort_order > ? AND id != ?",
        [base, utilitiesRow!['id']],
      );
      await db.update('categories', {'sort_order': base + 3}, where: 'id = ?', whereArgs: [utilitiesRow['id']]);
    }
    final ids = <String, int>{utilitiesCategory.name: utilitiesRow!['id'] as int};
    for (final (i, c) in [water, electricity, wifi].indexed) {
      final existing = await named(c.name);
      if (existing != null && (existing['kind'] ?? 'expense') == 'expense') {
        ids[c.name] = existing['id'] as int;
        continue;
      }
      final sort = base != null ? base + i : await _nextSort(db);
      final name = existing == null ? c.name : '${c.name} (expense)';
      final clash = existing == null ? null : await named(name);
      if (clash != null) {
        ids[c.name] = clash['id'] as int;
        continue;
      }
      ids[c.name] = await db.insert('categories', c.copyWith(name: name, sortOrder: sort).toMap()..remove('id'));
    }
    final utilId = ids[utilitiesCategory.name]!;
    for (final e in utilityKeywords.entries) {
      final target = ids[e.key]!;
      for (final kw in e.value) {
        final rule = await db.query('category_rules', where: 'keyword = ? COLLATE NOCASE', whereArgs: [kw], limit: 1);
        if (rule.isEmpty) {
          await db.insert('category_rules', CategoryRule(keyword: kw, categoryId: target).toMap()..remove('id'));
        } else if (rule.first['category_id'] == utilId && target != utilId) {
          await db.update('category_rules', {'category_id': target}, where: 'id = ?', whereArgs: [rule.first['id']]);
        }
      }
    }
  }

  static Future<int> _nextSort(DatabaseExecutor db) async {
    final r = await db.rawQuery("SELECT MAX(sort_order) AS m FROM categories WHERE kind = 'expense'");
    return ((r.first['m'] as int?) ?? 0) + 1;
  }

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

  /// Extra patterns for e-wallet / bank APP notifications (Maya, GCash,
  /// MariBank, BDO Pay), added in v12. The notification's title and text
  /// are read as one message whose sender is the app's package name, so
  /// the SMS patterns above (e.g. "You've paid ₱150.00 to 7-Eleven") work
  /// for notifications too; these cover the other common wordings.
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

  /// Adds the [notificationPatterns] that aren't there yet (by name), so
  /// the user's own edits and deletions of other patterns are kept.
  static Future<void> ensureNotificationPatterns(DatabaseExecutor db) async {
    for (final p in notificationPatterns) {
      final same = await db.query('sms_patterns', where: 'bank_name = ?', whereArgs: [p.bankName], limit: 1);
      if (same.isEmpty) await db.insert('sms_patterns', p.toMap());
    }
  }
}
