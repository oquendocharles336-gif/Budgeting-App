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

Tables: `cards` (also the accounts table: name, type, `balance`), `transactions`, `categories`, `category_rules`, `debts`, `debt_payments`, `budgets`, `settings`, `sms_patterns`.

- Money is `INTEGER` centavos. Dates are `INTEGER` milliseconds since epoch (local time).
- `PRAGMA foreign_keys = ON` on every open.
- `transactions`: `source` (`manual`/`csv_import`/`sms_parsed`/`bank_sync`), `external_id`, `dedup_hash`.
  Unique index on `(card_id, external_id) WHERE external_id IS NOT NULL`; indexes on `date`, `category_id`, `card_id`, `dedup_hash`.
- `budgets`: one row per month per category (`category_id NULL` = overall). Unique on `(month, IFNULL(category_id, 0))`.
  A new month copies the previous month's amounts; spending is always counted per month, so it "resets". Old months stay as history.
- Deleting a category moves its transactions to "Other". Deleting a card deletes its transactions (archive keeps them).

Migrations live in `lib/data/db/migrations.dart` as numbered steps. v1 = core schema + defaults, v2 = `sms_patterns`, v3 = `debts.debt_type`, `cards.mobile_number` (full e-wallet number, masked only at display time) and `transfer` transactions with `to_card_id`, v4 = `categories.kind`/`role` (separate income categories; "Other" lets the user type a label, stored in `transactions.custom_category`; "Borrowed money" income also creates a debt) and debt lender, interest type (simple/compound), rate period and term. `domain/debt/interest_calculator.dart` works out the monthly interest and payment. v5 = account balances: `cards.balance` and `transactions.affects_balance` (see "Balances" below). Only SQLite 3.9 features are used (Android 7): no UPSERT, RETURNING or window functions.

## Balances

- Accounts are the `cards` rows (bank card, e-wallet, ...) plus **Cash**, which has no row; its balance is the `cash_balance` setting. `NULL` account id = Cash everywhere.
- `data/repositories/account_ledger.dart` applies a transaction to balances: expense = minus on its account, income = plus, transfer = minus on `card_id`, plus on `to_card_id`.
- `TransactionRepository.insert / update / delete` change the row and the balances inside one SQLite transaction. Editing undoes the old effect, then applies the new one; deleting undoes it. Deleting an account undoes its transfers on the other side.
- `affects_balance` = 1 only for manual entries made since v5. Rows from before v5 and CSV/SMS imports are 0: the starting balance the user typed already includes them, so editing or deleting them never moves money twice.
- "Available balance" (Home, Budget, Wallets) = Cash + every non-credit, non-archived account. Credit cards show "available credit" separately.
- An expense or transfer larger than the paying account's balance asks for confirmation ("Insufficient balance") and can go below zero.

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

### Unlock method (chosen on first launch, changeable in Settings)

- **Phone screen lock**: offered only when `local_auth` `isDeviceSupported()` is true. `authenticate(biometricOnly: false)`, so fingerprint/face are used if enrolled and the phone PIN/pattern/password always works. The data key lives in Android Keystore / iOS Keychain (`flutter_secure_storage`, key `pitaka_device_key_v1`); the vault file only holds the recovery-key copy.
- **In-app PIN or password**: 6-12 digit PIN or 8+ character password, typed twice. Never stored: PBKDF2-HMAC-SHA256 (random salt, 600k iterations) derives the key that seals the data key, as before. Wrong tries are counted in secure storage (30 s wait after 5, doubling).
- The method is saved in secure storage (`pitaka_unlock_method`) and cross-checked with the vault (no password in the vault = phone lock).
- If the phone lock is removed later, the next launch asks the user to set an in-app PIN (the key is read from the keystore once and re-sealed under the PIN). If the keystore entry is gone too, the recovery key is the way back in.
- The app locks as soon as it goes to the background and shows a logo cover while inactive. File pickers, permission prompts and the phone's own unlock prompt run inside `LockGuard.run`, so leaving for them doesn't lock (up to 2 minutes).

### Encryption

- The database file (`pitaka_secure.db`) is encrypted with SQLCipher using a random 256-bit data key.
- `domain/security/vault.dart` keeps that key in `pitaka_vault.json`, sealed twice with AES-256-GCM: under a PBKDF2-HMAC-SHA256 key from the password (600k iterations) and under one from the 24-character recovery key. The password, recovery key and data key are never written in clear and nothing leaves the phone, so no one without them (developer included) can read the data or reset the password.
- `main.dart` shows sign-up / login / forgot-password before any provider exists. Locking (button or 30 s in the background) tears down the `ProviderScope`, closes the database and drops the key.
- Upgrading from an unencrypted `pitaka.db`: the first password set-up runs `sqlcipher_export` into the encrypted file, verifies it opens, saves the vault, then deletes the old file.
- Optional fingerprint unlock stores the data key in Android Keystore / iOS Keychain (`flutter_secure_storage`) behind a `local_auth` prompt.
- JSON backups are wrapped in a password-encrypted envelope (`domain/services/backup_crypto.dart`); CSV exports are plain and the app warns first.

## Branding

- `assets/logo/logo.svg` is the source; `logo.png` (1024x1024, transparent) is shown on the set-up and lock screens (`AppLogo` in `auth_widgets.dart`) and used for icons and splash.
- `logo_foreground.png` = the same logo with empty margin, for the Android adaptive icon. `splash_android12.png` = logo on a 1152 canvas for the Android 12+ splash circle.
- The Android icon/splash resources in `android/app/src/main/res` were generated from these. After replacing the PNGs, run `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` (configs are in `pubspec.yaml`).
- iOS: the project has no `ios/` folder yet. After `flutter create --platforms=ios .`, add `NSFaceIDUsageDescription` to `ios/Runner/Info.plist`, set `CFBundleDisplayName` to `Pitaka`, and set `ios: true` in both generator configs.

## Theme (60 / 30 / 10)

- `presentation/theme/app_palette.dart` holds every color as tokens: **main** (60%: backgrounds), **second** (30%: cards, containers, sheets, inputs), **accent** (10%: buttons, FAB, highlights, key numbers), plus `on*` text colors, status colors and the scrim.
- Default theme "Midnight": dark = midnight black / electric blue / sunset orange. The other palettes are built with the same structure from their hue.
- `_finish` nudges every text color to WCAG AA (4.5:1) on the surfaces it sits on; `test/presentation/theme_contrast_test.dart` checks all palettes in light and dark.
- `AppTheme` maps tokens onto the Material `ColorScheme` and component themes. Screens use the scheme or `context.tokens`; the only literal colors left are user data (card and category colors).
- Dialogs and bottom sheets dim the screen behind them with the `scrim` token.

## Motion (`presentation/widgets/motion/`)

- `cascade.dart`: `CascadeScope` + `CascadeIn` for list entrances. Rows fade and slide in 70 ms apart with ease-out, at most 12 rows, only once per screen (not on rebuilds or scrolling).
- `skeleton.dart`: layout-shaped loading placeholders (`LoadingView` uses them).
- `animated_icons.dart`: search ↔ close, lock ↔ unlock (spring with a small overshoot), plus ↔ close, check draw-in, menu ↔ close. Each is driven by one progress value, so closing plays the opening in reverse.
- `swipe_card_deck.dart`: the Wallets card deck. Cards follow the finger with a tilt, fling away with the release velocity or spring back, and the next card peeks below.
- Everything checks `MediaQuery.disableAnimations` (reduce motion) and disposes its controllers.

## Data prep

`domain/analytics/data_prep.dart` runs before every total and chart (Budget, Insights, budget alerts):
- It skips rows with no amount or date.
- Missing or unknown categories become "Uncategorized".
- It normalizes amounts, dates and text.
- It removes duplicates (same kind, amount, day, description and account) when any copy was imported. Identical rows that were all typed by hand are kept.

## Debts (v6)

- `debts.origin`: `new` or `existing`.
- `transactions.debt_id`: the expense created by a new debt (`ON DELETE SET NULL`).
- A **new** debt creates an expense in the "Debt" category in the same SQLite transaction. That expense doesn't move account balances.
- An **existing** debt is only a reminder.
- Payments only reduce the remaining amount.
- `domain/debt/debt_reminder.dart` computes the reminder time: the deadline minus 2 days, at 9:00. If that time has passed, the reminder goes out at the next reasonable time.
- `DebtService` schedules or cancels through the `DebtReminderScheduler` interface, which `NotificationService` implements. Reminders are re-created on every unlock, and the plugin's boot receiver restores them after a reboot.

## Optimistic saves

`presentation/providers/optimistic_providers.dart` holds pending transactions and budgets, which are laid over the database results. The form closes and shows a "Saved" check right away. When the write finishes, the data refreshes and the pending copy is dropped. If the write fails, the change is rolled back and a message offers "Try again".

