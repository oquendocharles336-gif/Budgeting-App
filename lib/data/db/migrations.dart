import 'package:sqflite_sqlcipher/sqflite.dart';

import 'default_data.dart';

typedef MigrationStep = Future<void> Function(DatabaseExecutor db);

/// Versioned schema migrations.
///
/// Rules:
///  * Never edit a step that has shipped. Add a new version instead.
///  * Each step moves the schema from version N-1 to N.
///  * A fresh install runs every step from 1 up to [latestVersion].
///
/// Only SQLite features available on Android 7 (SQLite 3.9) are used:
/// no UPSERT, no RETURNING, no window functions.
class Migrations {
  Migrations._();

  static final Map<int, MigrationStep> _steps = {
    1: _v1CoreSchema,
    2: _v2SmsPatterns,
    3: _v3DebtTypeWalletNumberTransfers,
    4: _v4IncomeCategoriesAndDebtInterest,
  };

  static int get latestVersion => _steps.keys.reduce((a, b) => a > b ? a : b);

  static Future<void> run(DatabaseExecutor db, int fromVersion, int toVersion) async {
    for (var v = fromVersion + 1; v <= toVersion; v++) {
      final step = _steps[v];
      if (step == null) {
        throw StateError('Missing migration for version $v');
      }
      await step(db);
    }
  }

  // ---------------------------------------------------------------------------
  // v1: core tables
  // ---------------------------------------------------------------------------
  static Future<void> _v1CoreSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE cards (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        nickname    TEXT    NOT NULL,
        last4       TEXT    NOT NULL CHECK (length(last4) = 4),
        card_type   TEXT    NOT NULL,
        color       INTEGER NOT NULL,
        archived    INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE categories (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL COLLATE NOCASE UNIQUE,
        icon        TEXT    NOT NULL,
        color       INTEGER NOT NULL,
        is_default  INTEGER NOT NULL DEFAULT 0,
        sort_order  INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE transactions (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        amount       INTEGER NOT NULL CHECK (amount > 0),
        kind         TEXT    NOT NULL DEFAULT 'expense' CHECK (kind IN ('expense', 'income')),
        description  TEXT    NOT NULL,
        category_id  INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        card_id      INTEGER REFERENCES cards(id) ON DELETE RESTRICT,
        date         INTEGER NOT NULL,
        notes        TEXT,
        source       TEXT    NOT NULL DEFAULT 'manual'
                     CHECK (source IN ('manual', 'csv_import', 'sms_parsed', 'bank_sync')),
        external_id  TEXT,
        dedup_hash   TEXT,
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL
      )''');
    // One external_id per card. Partial index so manual rows (NULL) don't collide.
    await db.execute('''
      CREATE UNIQUE INDEX ux_transactions_card_external
      ON transactions(card_id, external_id) WHERE external_id IS NOT NULL''');
    await db.execute('CREATE INDEX ix_transactions_date ON transactions(date)');
    await db.execute('CREATE INDEX ix_transactions_category ON transactions(category_id)');
    await db.execute('CREATE INDEX ix_transactions_card ON transactions(card_id)');
    await db.execute('CREATE INDEX ix_transactions_hash ON transactions(dedup_hash)');

    await db.execute('''
      CREATE TABLE category_rules (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        keyword      TEXT    NOT NULL COLLATE NOCASE UNIQUE,
        category_id  INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
        priority     INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX ix_rules_category ON category_rules(category_id)');

    await db.execute('''
      CREATE TABLE debts (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        creditor          TEXT    NOT NULL,
        total_amount      INTEGER NOT NULL CHECK (total_amount > 0),
        initial_paid      INTEGER NOT NULL DEFAULT 0 CHECK (initial_paid >= 0),
        due_date          INTEGER,
        interest_rate_bp  INTEGER,
        notes             TEXT,
        is_paid           INTEGER NOT NULL DEFAULT 0,
        created_at        INTEGER NOT NULL,
        paid_at           INTEGER
      )''');
    await db.execute('CREATE INDEX ix_debts_due ON debts(due_date)');

    await db.execute('''
      CREATE TABLE debt_payments (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        debt_id  INTEGER NOT NULL REFERENCES debts(id) ON DELETE CASCADE,
        amount   INTEGER NOT NULL CHECK (amount > 0),
        date     INTEGER NOT NULL,
        note     TEXT
      )''');
    await db.execute('CREATE INDEX ix_debt_payments_debt ON debt_payments(debt_id)');

    await db.execute('''
      CREATE TABLE budgets (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        month        TEXT    NOT NULL,
        category_id  INTEGER REFERENCES categories(id) ON DELETE CASCADE,
        amount       INTEGER NOT NULL CHECK (amount >= 0)
      )''');
    // IFNULL so there is only one overall (NULL category) budget per month.
    await db.execute('''
      CREATE UNIQUE INDEX ux_budgets_month_category
      ON budgets(month, IFNULL(category_id, 0))''');

    await db.execute('''
      CREATE TABLE settings (
        key    TEXT PRIMARY KEY,
        value  TEXT
      )''');

    // Default categories and keyword rules.
    for (final c in DefaultData.categories) {
      // kind/role columns are added in v4.
      await db.insert('categories', c.toMap()..remove('kind')..remove('role'));
    }
    for (final r in DefaultData.rules) {
      await db.insert('category_rules', r.toMap());
    }
    await db.insert('settings', {'key': 'currency', 'value': 'PHP'});
  }

  // ---------------------------------------------------------------------------
  // v2: user-editable SMS patterns (shows how a later migration is added)
  // ---------------------------------------------------------------------------
  static Future<void> _v2SmsPatterns(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sms_patterns (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        bank_name       TEXT    NOT NULL,
        sender_pattern  TEXT    NOT NULL DEFAULT '',
        body_pattern    TEXT    NOT NULL,
        kind            TEXT    NOT NULL DEFAULT 'expense',
        enabled         INTEGER NOT NULL DEFAULT 1
      )''');
    for (final p in DefaultData.smsPatterns) {
      await db.insert('sms_patterns', p.toMap());
    }
  }

  // ---------------------------------------------------------------------------
  // v3: debt type, e-wallet mobile number, transfers between accounts
  // ---------------------------------------------------------------------------
  static Future<void> _v3DebtTypeWalletNumberTransfers(DatabaseExecutor db) async {
    await db.execute("ALTER TABLE debts ADD COLUMN debt_type TEXT NOT NULL DEFAULT 'other'");

    // Full number is stored; it is only masked when displayed.
    await db.execute('ALTER TABLE cards ADD COLUMN mobile_number TEXT');

    // SQLite can't change a CHECK constraint in place, so the transactions
    // table is rebuilt to allow kind = 'transfer' and add to_card_id
    // (destination of a transfer; NULL = cash). No table references
    // transactions, so dropping the old one is safe with foreign keys on.
    await db.execute('''
      CREATE TABLE transactions_v3 (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        amount       INTEGER NOT NULL CHECK (amount > 0),
        kind         TEXT    NOT NULL DEFAULT 'expense' CHECK (kind IN ('expense', 'income', 'transfer')),
        description  TEXT    NOT NULL,
        category_id  INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        card_id      INTEGER REFERENCES cards(id) ON DELETE RESTRICT,
        to_card_id   INTEGER REFERENCES cards(id) ON DELETE RESTRICT,
        date         INTEGER NOT NULL,
        notes        TEXT,
        source       TEXT    NOT NULL DEFAULT 'manual'
                     CHECK (source IN ('manual', 'csv_import', 'sms_parsed', 'bank_sync')),
        external_id  TEXT,
        dedup_hash   TEXT,
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL
      )''');
    const cols = 'id, amount, kind, description, category_id, card_id, date, notes, '
        'source, external_id, dedup_hash, created_at, updated_at';
    await db.execute('INSERT INTO transactions_v3 ($cols) SELECT $cols FROM transactions');
    await db.execute('DROP TABLE transactions');
    await db.execute('ALTER TABLE transactions_v3 RENAME TO transactions');
    await db.execute('''
      CREATE UNIQUE INDEX ux_transactions_card_external
      ON transactions(card_id, external_id) WHERE external_id IS NOT NULL''');
    await db.execute('CREATE INDEX ix_transactions_date ON transactions(date)');
    await db.execute('CREATE INDEX ix_transactions_category ON transactions(category_id)');
    await db.execute('CREATE INDEX ix_transactions_card ON transactions(card_id)');
    await db.execute('CREATE INDEX ix_transactions_to_card ON transactions(to_card_id)');
    await db.execute('CREATE INDEX ix_transactions_hash ON transactions(dedup_hash)');
  }

  // ---------------------------------------------------------------------------
  // v4: income categories, typed "Other" labels, debt lender + interest terms
  // ---------------------------------------------------------------------------
  static Future<void> _v4IncomeCategoriesAndDebtInterest(DatabaseExecutor db) async {
    await db.execute("ALTER TABLE categories ADD COLUMN kind TEXT NOT NULL DEFAULT 'expense'");
    await db.execute('ALTER TABLE categories ADD COLUMN role TEXT');
    await db.update('categories', {'role': 'other'}, where: 'id = ?', whereArgs: [DefaultData.other]);
    await DefaultData.ensureIncomeCategories(db);
    // Income used to be filed under expense categories; move it to "Other income".
    await db.execute('''
      UPDATE transactions
      SET category_id = (SELECT id FROM categories WHERE kind = 'income' AND role = 'other' LIMIT 1)
      WHERE kind = 'income' ''');

    // What the user typed after picking "Other".
    await db.execute('ALTER TABLE transactions ADD COLUMN custom_category TEXT');

    await db.execute('ALTER TABLE debts ADD COLUMN lender_type TEXT');
    await db.execute('ALTER TABLE debts ADD COLUMN lender_detail TEXT');
    await db.execute("ALTER TABLE debts ADD COLUMN interest_type TEXT NOT NULL DEFAULT 'simple'");
    await db.execute("ALTER TABLE debts ADD COLUMN interest_period TEXT NOT NULL DEFAULT 'month'");
    await db.execute('ALTER TABLE debts ADD COLUMN term_months INTEGER');
  }
}
