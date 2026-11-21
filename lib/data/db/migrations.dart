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
    5: _v5AccountBalances,
    6: _v6DebtOriginAndLinkedExpense,
    7: _v7PayLaterLoansFeesBusiness,
    8: _v8StockLedgerCapitalWithdrawIdempotency,
    9: _v9RemovePayLaterLoanPaymentMethod,
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

  // ---------------------------------------------------------------------------
  // v5: account balances (cards / e-wallets act as accounts; cash has its own
  // balance in settings) and which transactions moved a balance
  // ---------------------------------------------------------------------------
  static Future<void> _v5AccountBalances(DatabaseExecutor db) async {
    // The `cards` table already is the accounts table (id, nickname = name,
    // card_type = type), and transactions already point at it through
    // card_id / to_card_id, so only the balance is new. Existing accounts
    // start at 0 and the user enters their current amount.
    await db.execute('ALTER TABLE cards ADD COLUMN balance INTEGER NOT NULL DEFAULT 0');

    // 1 = this row changed an account balance when it was saved, so editing
    // or deleting it must undo that. Rows saved before v5 (and imports,
    // which the typed starting balance already includes) stay 0, so
    // deleting an old expense never adds money that was never taken out.
    await db.execute('ALTER TABLE transactions ADD COLUMN affects_balance INTEGER NOT NULL DEFAULT 0');
  }

  // ---------------------------------------------------------------------------
  // v6: new vs existing debts, and the expense a new debt creates
  // ---------------------------------------------------------------------------
  static Future<void> _v6DebtOriginAndLinkedExpense(DatabaseExecutor db) async {
    // 'new' = money just received/spent: it also has a linked expense.
    // 'existing' = only a reminder. Debts added before v6 were reminders.
    await db.execute("ALTER TABLE debts ADD COLUMN origin TEXT NOT NULL DEFAULT 'existing'");
    // The expense a new debt created. Deleting the debt without removing
    // the expense just unlinks it.
    await db.execute('ALTER TABLE transactions ADD COLUMN debt_id INTEGER REFERENCES debts(id) ON DELETE SET NULL');
    await db.execute('CREATE INDEX ix_transactions_debt ON transactions(debt_id)');
    await DefaultData.ensureDebtCategory(db);
  }

  // ---------------------------------------------------------------------------
  // v7: Pay Later, Loans "paid" state, transfer fees, business side
  // ---------------------------------------------------------------------------
  static Future<void> _v7PayLaterLoansFeesBusiness(DatabaseExecutor db) async {
    // Only new columns (ALTER TABLE ... ADD COLUMN) and new tables, so
    // every existing row is kept as it is.

    // The "Fees" expense a transfer fee created points at its transfer.
    // No REFERENCES: the repository removes it together with the transfer
    // (so its balance change is undone too).
    await db.execute('ALTER TABLE transactions ADD COLUMN fee_of_id INTEGER');
    await db.execute('CREATE INDEX ix_transactions_fee_of ON transactions(fee_of_id)');
    // 1 = a transfer into business capital: money leaves the personal
    // account and does not arrive in another personal account.
    await db.execute('ALTER TABLE transactions ADD COLUMN to_capital INTEGER NOT NULL DEFAULT 0');
    // Loans section: when the user marked a "Loan" transaction as paid.
    await db.execute('ALTER TABLE transactions ADD COLUMN loan_paid_at INTEGER');

    await db.execute('''
      CREATE TABLE pay_later (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        item           TEXT    NOT NULL,
        amount         INTEGER NOT NULL CHECK (amount > 0),
        category_id    INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        purchase_date  INTEGER NOT NULL,
        due_date       INTEGER NOT NULL,
        status         TEXT    NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'paid')),
        paid_at        INTEGER,
        expense_tx_id  INTEGER,
        notes          TEXT,
        created_at     INTEGER NOT NULL,
        updated_at     INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX ix_pay_later_due ON pay_later(status, due_date)');
    // One expense per Pay Later item, ever.
    await db.execute('''
      CREATE UNIQUE INDEX ux_pay_later_expense
      ON pay_later(expense_tx_id) WHERE expense_tx_id IS NOT NULL''');

    // Business capital: + money moved in from the personal budget.
    await db.execute('''
      CREATE TABLE capital_entries (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        amount          INTEGER NOT NULL CHECK (amount != 0),
        kind            TEXT    NOT NULL DEFAULT 'deposit',
        note            TEXT,
        date            INTEGER NOT NULL,
        transaction_id  INTEGER,
        created_at      INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX ix_capital_date ON capital_entries(date)');
    await db.execute('CREATE INDEX ix_capital_tx ON capital_entries(transaction_id)');

    await db.execute('''
      CREATE TABLE inventory_items (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        quantity    REAL    NOT NULL DEFAULT 0 CHECK (quantity >= 0),
        unit        TEXT    NOT NULL,
        low_stock   REAL,
        photo_path  TEXT,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE products (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        price       INTEGER NOT NULL CHECK (price >= 0),
        photo_path  TEXT,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE orders (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        buyer             TEXT    NOT NULL,
        order_date        INTEGER NOT NULL,
        total             INTEGER NOT NULL CHECK (total >= 0),
        paid_amount       INTEGER NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
        tendered          INTEGER,
        change_given      INTEGER,
        method            TEXT    NOT NULL DEFAULT 'cash'
                          CHECK (method IN ('cash', 'maya', 'maribank', 'bdo')),
        status            TEXT    NOT NULL DEFAULT 'complete'
                          CHECK (status IN ('complete', 'paid', 'delivered', 'delivered_unpaid')),
        notes             TEXT,
        budget_tx_id      INTEGER,
        added_to_budget_at INTEGER,
        created_at        INTEGER NOT NULL,
        updated_at        INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX ix_orders_date ON orders(order_date)');
    await db.execute('CREATE INDEX ix_orders_budget_tx ON orders(budget_tx_id)');

    // Product name and price are copied, so old orders keep their history
    // after a product is renamed, repriced or deleted.
    await db.execute('''
      CREATE TABLE order_items (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id    INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_id  INTEGER REFERENCES products(id) ON DELETE SET NULL,
        name        TEXT    NOT NULL,
        unit_price  INTEGER NOT NULL CHECK (unit_price >= 0),
        quantity    INTEGER NOT NULL CHECK (quantity > 0)
      )''');
    await db.execute('CREATE INDEX ix_order_items_order ON order_items(order_id)');

    await DefaultData.ensureV7Categories(db);
  }

  // ---------------------------------------------------------------------------
  // v8: stock ledger + recipes, capital withdrawals, safe retries
  // ---------------------------------------------------------------------------
  static Future<void> _v8StockLedgerCapitalWithdrawIdempotency(DatabaseExecutor db) async {
    // One row per user action that must happen once (a save, a payment, a
    // transfer). A retry or double tap with the same key finds the row and
    // returns the first result instead of writing again.
    await db.execute('''
      CREATE TABLE op_keys (
        key         TEXT    PRIMARY KEY,
        result      INTEGER,
        created_at  INTEGER NOT NULL
      )''');

    // A transfer out of business capital into a personal account.
    await db.execute('ALTER TABLE transactions ADD COLUMN from_capital INTEGER NOT NULL DEFAULT 0');

    // Capital ledger: deposit, withdrawal, fee, sales_added. v7's table
    // didn't allow amount 0 (needed for "sales added" history rows, which
    // don't change capital), so it is rebuilt. Nothing references it.
    await db.execute('''
      CREATE TABLE capital_entries_v8 (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        amount          INTEGER NOT NULL,
        kind            TEXT    NOT NULL DEFAULT 'deposit'
                        CHECK (kind IN ('deposit', 'withdrawal', 'fee', 'sales_added')),
        memo_amount     INTEGER,
        note            TEXT,
        date            INTEGER NOT NULL,
        transaction_id  INTEGER,
        created_at      INTEGER NOT NULL
      )''');
    await db.execute('''
      INSERT INTO capital_entries_v8 (id, amount, kind, note, date, transaction_id, created_at)
      SELECT id, amount,
             CASE WHEN kind IN ('deposit', 'withdrawal', 'fee', 'sales_added') THEN kind ELSE 'deposit' END,
             note, date, transaction_id, created_at
      FROM capital_entries''');
    await db.execute('DROP TABLE capital_entries');
    await db.execute('ALTER TABLE capital_entries_v8 RENAME TO capital_entries');
    await db.execute('CREATE INDEX ix_capital_date ON capital_entries(date)');
    await db.execute('CREATE INDEX ix_capital_tx ON capital_entries(transaction_id)');

    // Stock ledger: the stock shown is always SUM(change) per item.
    await db.execute('''
      CREATE TABLE stock_movements (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id     INTEGER NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
        change      REAL    NOT NULL,
        reason      TEXT    NOT NULL
                    CHECK (reason IN ('restock', 'order', 'adjustment', 'order_cancelled')),
        order_id    INTEGER,
        note        TEXT,
        date        INTEGER NOT NULL,
        created_at  INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX ix_stock_item ON stock_movements(item_id)');
    await db.execute('CREATE INDEX ix_stock_order ON stock_movements(order_id)');
    // Existing stock becomes each item's first ledger row, so nothing changes on screen.
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT INTO stock_movements (item_id, change, reason, note, date, created_at)
      SELECT id, quantity, 'adjustment', 'Starting stock', $now, $now
      FROM inventory_items WHERE quantity > 0''');

    // Recipe: how much of each ingredient one unit of a product uses.
    await db.execute('''
      CREATE TABLE product_ingredients (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id  INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        item_id     INTEGER NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
        quantity    REAL    NOT NULL CHECK (quantity > 0),
        UNIQUE (product_id, item_id)
      )''');
    await db.execute('CREATE INDEX ix_ingredients_item ON product_ingredients(item_id)');

    // Cancelled orders return their stock and leave sales totals.
    await db.execute('ALTER TABLE orders ADD COLUMN cancelled_at INTEGER');
  }

  // ---------------------------------------------------------------------------
  // v9: Pay Later removed, loan payments with a method, one "Delivered" status
  // ---------------------------------------------------------------------------
  static Future<void> _v9RemovePayLaterLoanPaymentMethod(DatabaseExecutor db) async {
    // 1. The Pay Later feature is gone. Paid items already created a normal
    //    expense, which stays in Activity. Unpaid items are still money owed,
    //    so they move to Debts (installment, same amount and due date)
    //    instead of disappearing. A fresh install has an empty table here.
    if (await _tableExists(db, 'pay_later')) {
      await db.execute('''
        INSERT INTO debts (creditor, total_amount, initial_paid, due_date, notes, is_paid, created_at, debt_type, origin)
        SELECT item, amount, 0, due_date,
               'Moved from Pay Later' || CASE WHEN notes IS NULL OR notes = '' THEN '' ELSE ': ' || notes END,
               0, purchase_date, 'installment', 'existing'
        FROM pay_later
        WHERE status = 'unpaid' AND amount > 0''');
      await db.execute('DROP INDEX IF EXISTS ux_pay_later_expense');
      await db.execute('DROP INDEX IF EXISTS ix_pay_later_due');
      await db.execute('DROP TABLE pay_later');
    }

    // 2. Loans: how a loan was paid ('cash' or 'ewallet') on the loan row,
    //    and on the payment expense the loan it pays (so the payment counts
    //    in the budget like any other expense, and is removed with the loan).
    await db.execute('ALTER TABLE transactions ADD COLUMN loan_paid_method TEXT');
    await db.execute('ALTER TABLE transactions ADD COLUMN loan_payment_of_id INTEGER');
    await db.execute('CREATE INDEX ix_transactions_loan_payment ON transactions(loan_payment_of_id)');

    // 3. Orders: "Delivered / Not Paid" is merged into "Delivered" (what is
    //    still owed is shown from the amounts, not the status). The old value
    //    stays allowed by the CHECK so old backups still restore.
    await db.execute("UPDATE orders SET status = 'delivered' WHERE status = 'delivered_unpaid'");
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String name) async {
    final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [name]);
    return rows.isNotEmpty;
  }
}
