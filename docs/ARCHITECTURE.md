# Architecture

Pitaka is an offline Flutter app. Everything lives in one SQLite file on the phone.

## Layers

```
presentation/   screens, widgets, theme, Riverpod providers
      │  (calls repositories and services only — never SQL, never a source directly)
      ▼
domain/         pure logic + services
                csv/        CsvParser, CsvStatementReader, DateParser
                sms/        SmsParser
                import/     TransactionImportService, Deduplicator, AutoCategorizer
                budget/     BudgetCalculator
                analytics/  SpendingAnalytics
                services/   TransactionService, DebtService, BudgetAlertService,
                            NotificationService, BackupService, AppLockService
      │
      ▼
data/           db/ (open, migrations, default + sample data)
                models/ (plain Dart classes with toMap/fromMap)
                repositories/ (all SQL lives here)
                sources/ (TransactionSource + implementations, SMS channel)
```

`core/` holds small helpers used everywhere: money (integer centavos), dates, text normalization, legal text, feature flags.

## Where card transactions come from

Every source implements one interface and only *produces* `RawTransaction`s:

```dart
abstract class TransactionSource {
  String get id;
  String get displayName;
  bool get requiresNetwork;
  Future<bool> isAvailable();
  Future<List<RawTransaction>> fetchTransactions({required PaymentCard card, DateTime? since});
}
```

The model is called `PaymentCard` instead of `Card` so it doesn't clash with Flutter's `Card` widget.

| Source | Status | Notes |
|---|---|---|
| `ManualEntrySource` | Working | The add form goes through `TransactionImportService.saveManual` |
| `CsvImportSource` | Working | Column-mapping screen + preview |
| `SmsParserSource` | Working (Android) | Opt-in permission, user-editable regex patterns, review before save |
| `BankSyncSource` | Placeholder | Returns "not available", hidden behind `FeatureFlags.bankSync` |

All sources feed one pipeline:

```
source.fetchTransactions()
   → normalize (trim, collapse spaces, positive amount)
   → auto-categorize (keyword rules, longest/priority wins, fallback "Other")
   → de-duplicate (card + external_id, then card + day + amount + kind + description hash, counted)
   → review screen (user ticks/unticks, changes categories)
   → commit (one SQLite transaction) → budget alert check
```

## Database

Tables: `cards`, `transactions`, `categories`, `category_rules`, `debts`, `debt_payments`, `budgets`, `settings`, `sms_patterns`.

- Money is `INTEGER` centavos. Dates are `INTEGER` milliseconds since epoch (local time).
- `PRAGMA foreign_keys = ON` on every open.
- `transactions`: `source` (`manual`/`csv_import`/`sms_parsed`/`bank_sync`), `external_id`, `dedup_hash`.
  Unique index on `(card_id, external_id) WHERE external_id IS NOT NULL`; indexes on `date`, `category_id`, `card_id`, `dedup_hash`.
- `budgets`: one row per month per category (`category_id NULL` = overall). Unique on `(month, IFNULL(category_id, 0))`.
  A new month copies the previous month's amounts; spending is always counted per month, so it "resets". Old months stay as history.
- Deleting a category moves its transactions to "Other". Deleting a card deletes its transactions (archive keeps them).

Migrations live in `lib/data/db/migrations.dart` as numbered steps. v1 = core schema + defaults, v2 = `sms_patterns`, v3 = `debts.debt_type`, `cards.mobile_number` (full e-wallet number, masked only at display time) and `transfer` transactions with `to_card_id`, v4 = `categories.kind`/`role` (separate income categories; "Other" lets the user type a label, stored in `transactions.custom_category`; "Borrowed money" income also creates a debt) and debt lender, interest type (simple/compound), rate period and term. `domain/debt/interest_calculator.dart` works out the monthly interest and payment. Only SQLite 3.9 features are used (Android 7): no UPSERT, RETURNING or window functions.

## State management (Riverpod)

- Repositories and services are plain `Provider`s.
- Screens read data from `FutureProvider`s in `data_providers.dart`.
- Every query provider watches `dataRevisionProvider`. After any write, the UI calls `ref.refreshData()` (bumps the revision) and every visible screen reloads. Simple and consistent for a local database.
- App-wide settings (theme, currency, terms, lock) are `Notifier`s seeded from settings loaded before the first frame.

## Security & privacy

- No network code. The release manifest has no `INTERNET` permission. Android auto-backup is off (`allowBackup="false"`).
- PIN: salted SHA-256 in `settings`, never the PIN itself. Biometrics via `local_auth` (OS-handled).
- The lock screen is drawn above the navigator, so it covers any open screen. It re-locks after 30 s in the background.
- SMS: read on device through a small Java `MethodChannel` (no third-party SMS plugin). OTP-looking messages are skipped.

## Login and encryption

- The database file (`pitaka_secure.db`) is encrypted with SQLCipher using a random 256-bit data key.
- `domain/security/vault.dart` keeps that key in `pitaka_vault.json`, sealed twice with AES-256-GCM: under a PBKDF2-HMAC-SHA256 key from the password (600k iterations) and under one from the 24-character recovery key. The password, recovery key and data key are never written in clear and nothing leaves the phone, so no one without them (developer included) can read the data or reset the password.
- `main.dart` shows sign-up / login / forgot-password before any provider exists. Locking (button or 30 s in the background) tears down the `ProviderScope`, closes the database and drops the key.
- Upgrading from an unencrypted `pitaka.db`: the first password set-up runs `sqlcipher_export` into the encrypted file, verifies it opens, saves the vault, then deletes the old file.
- Optional fingerprint unlock stores the data key in Android Keystore / iOS Keychain (`flutter_secure_storage`) behind a `local_auth` prompt.
- JSON backups are wrapped in a password-encrypted envelope (`domain/services/backup_crypto.dart`); CSV exports are plain and the app warns first.
