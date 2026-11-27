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

Migrations live in `lib/data/db/migrations.dart` as numbered steps. v1 = core schema + defaults, v2 = `sms_patterns`, v3 = `debts.debt_type`, `cards.mobile_number` (full e-wallet number, masked only at display time) and `transfer` transactions with `to_card_id`, v4 = `categories.kind`/`role` (separate income categories; "Other" lets the user type a label, stored in `transactions.custom_category`; "Borrowed money" income also creates a debt) and debt lender, interest type (simple/compound), rate period and term. `domain/debt/interest_calculator.dart` works out the monthly interest and payment. v5 = account balances: `cards.balance` and `transactions.affects_balance` (see "Balances" below). v12 (app 1.6.0) = `debts.due_day` / `due_from` (a monthly payment day; `domain/debt/monthly_due.dart` works out the next due date and overdue months, one recorded payment per month), "Bills" renamed to "Utilities" plus Water / Electricity / WiFi (`DefaultData.ensureUtilityCategories`, also run after restoring an older backup and after "Delete all"), `orders.fulfillment` (Pending / For Pick-up / Delivered; the payment status Unpaid / Partially Paid / Paid is derived from `paid_amount`), and `cards.notify_app` / `auto_track_since` for free e-wallet tracking (`PaymentNotificationListener.java` keeps notifications from connected apps; `domain/services/auto_track_service.dart` parses them with the SMS patterns and saves them as balance-moving transactions). Only SQLite 3.9 features are used (Android 7): no UPSERT, RETURNING or window functions.

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

- One network request only: the optional update check (`data/sources/release_feed.dart`, HTTPS GET of the public GitHub Releases API for the latest release, no user data, no token). That is the only reason for the `INTERNET` permission. Android auto-backup is off (`allowBackup="false"`).
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

## Design system: Pitaka (Figma "Pitaka — Loans & Budget redesign")

- `presentation/theme/app_palette.dart`: the Figma variables. `PitakaColors` holds the raw values (Theme · Light, Theme · Dark, Accent · Sunset, Accent · Teal); `ThemeTokens` is one resolved theme: **main** (background `#F5F7FB` / `#0A0E1A`), **second** (flat cards, sheets, bars: white / navy `#111C38`), **secondHigh** (tracks, skeletons, icon bubbles), **outline** (1px card border), **accent** (brand fill `#FF6B35` or `#0D9488`), **accentContainer** (tonal pill: "Paid", selected tab, nav pill), hero gradient, status colors with containers (badges, banners), `infoContainer` (preview panel), `inverseSurface` (toasts) and the scrim.
- Settings offers the two Figma accents (Sunset, Teal). Any other saved or custom color (older versions offered more) gets the same structure from its hue (`AppPalettes.fromSeed`); the old default id opens Sunset.
- Text colors are nudged to WCAG AA on the surfaces they sit on; `test/presentation/theme_contrast_test.dart` checks every accent in light and dark and pins the Figma values. The brand fill itself is used exactly as designed (white bold labels on `#FF6B35` measure 2.84:1); the test records that value so changing it is deliberate.
- `presentation/theme/app_theme.dart`: `Space`, `Radii` and `Motion` (Figma dimensions and motion notes: 200 ms fades, 450 ms count-up, 600 ms bar ease, 6 s Undo), and `AppTheme`, which maps the tokens onto the Material `ColorScheme` and component themes (pill buttons, flat bordered cards, 28px sheets with a grab handle, 24px dialogs, dark toasts). Typeface: Plus Jakarta Sans, bundled in `assets/fonts` (OFL).
- Components (`presentation/widgets/common.dart`, `status_badge.dart`): `AppCard`, `HeroCard`, `PillTabs`, `TonalPillButton`, `IconBubble`, `StatusBadge`, `EmptyState`, `SectionHeader`, `BudgetProgressBar`, `MonthSwitcher`, `confirm()` (tonal or red action), `showSnack` / `showSavedSnack` (toast with green check and accent action).
- Navigation: a flat five-tab bar (Home, Activity, Budget, Wallets, Insights; Business is added at the end in Business Mode) with a tonal pill behind the selected icon. "+" is a floating button on Home and Activity. Insights only moves the shared selected month while it is the visible tab (`AnalyticsScreen.syncMonth`), so Budget can still browse earlier months.
- Screens read colors from the scheme or `context.tokens`; the only literal colors left are user data (card and category colors).

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


## v7: Pay Later, Loans, transfer fees, business side

Migration v7 only adds columns and tables (no rebuilds), so existing rows are untouched.

- `transactions.fee_of_id`: the "Fees" expense a transfer fee created, pointing at its transfer. `TransactionService.createTransfer` saves transfer + fee in one SQLite transaction (`TransactionRepository.insertTransfer`). Source goes down by amount + fee, destination gets the amount, and only the fee counts as spending. The fee is always shown in a confirmation before saving.
- `transactions.to_capital`: a transfer into business capital. `AccountLedger.effects` only takes the money out of the source (a NULL `to_card_id` here does not mean Cash).
- `transactions.loan_paid_at`: the Loans section's "Paid" state for rows in the "Loan" category (`CategoryRole.loanRecord`). Marking paid changes only that column: no new expense, so nothing is counted twice. Undo resets it.
- `pay_later`: purchases paid later. Unpaid items are not spending. `PayLaterRepository.markPaid` re-reads the row inside the SQLite transaction and creates the expense only if it is still unpaid (plus a unique index on `expense_tx_id`). Reminders reuse `DebtReminders.scheduleTime` (2 days before, 9:00 AM) through `PayLaterReminderScheduler`, implemented by `NotificationService` (ids 10,000,000 + item id).
- Business: `capital_entries`, `inventory_items`, `products`, `orders`, `order_items`. Order items copy the product's name and price. `orders.budget_tx_id` links a sale to the income "Add to Budget" created; `OrderRepository.addToBudget` picks eligible orders (fully paid, not yet added) inside the transaction and flags them only where the flag is still empty.
- `data/repositories/linked_records.dart`: when transactions are deleted, removes their fee rows and loan payments (undoing balances), their capital entries, marks a loan unpaid when its payment is deleted, and clears the "added to budget" flag on orders.
- New built-in categories (`DefaultData.ensureV7Categories`): "Fees", "Loan" and the "Business / sales" income category (an existing one with the same name is tagged, not duplicated).
- Photos: `data/sources/photo_store.dart` uses `image_picker` (system camera and photo picker, so no CAMERA or storage permission on Android), max 1080 px, JPEG quality 70, saved under `<app documents>/business_photos`. `PhotoService.pick` runs inside `LockGuard.run`. Photos are not in backups; "Delete all my data" deletes the folder.
- Sales analytics: `BusinessDataPrep.clean` applies the existing data-prep rules (and `PrepReport`) to orders before `SalesAnalytics`.
- Insights: `InsightsRange` limits the month switcher, swipe and month picker to the first month with spending through the current month.
- Backup table order now inserts `debts` before `transactions` (`transactions.debt_id` references debts).

## v8: stock ledger, capital withdrawals, safe retries, encrypted photos

- `op_keys`: one row per user action. Writes that could repeat (add, transfer, restock, order save, payment, capital move) run through `OpGuard.once(txn, key, ...)` in their SQLite transaction, so a double tap or "Try again" returns the first result and writes nothing. Keys are pruned after 30 days.
- Optimistic UI everywhere: `widgets/optimistic.dart` (`OptimisticWrite.run`) shows the change and "Saved" at once using `providers/pending_providers.dart` (or `pendingTransactionsProvider` for transfers), writes in the background, and on failure removes the preview and offers "Try again" with the same op key. Rules the user must fix (capital limit, short stock, validation) show a message instead of "Try again".
- Stock ledger `stock_movements` (restock / order / adjustment / order_cancelled). Stock = `SUM(change)`; `inventory_items.quantity` is no longer read (v8 copied it into a "Starting stock" row). Recipes live in `product_ingredients`. `StockPlan` (pure) plans an order's rows from what it should use vs what it already holds, so re-running adds nothing, edits/cancels/deletes add reversing rows, and use is capped at what's available (never below zero). Payment and status saves go through `OrderRepository.saveHeader` and never touch stock. `orders.cancelled_at` marks cancelled orders (left out of sales and "Add to Budget").
- Capital ledger kinds: deposit, withdrawal, fee, sales_added (amount 0, `memo_amount` = income added). Balance = sum. Withdrawals are transfers with `transactions.from_capital = 1` (only the personal destination moves); the limit is re-checked inside the SQLite transaction (`CapitalMath`).
- Photos: `PhotoCrypto` (AES-256-GCM, header "PKPH"+v1, nonce, tag) with the key in `flutter_secure_storage` (`pitaka_photo_key_v1`). Files end in `.enc`. `PhotoService.read` decrypts into an in-memory LRU cache; nothing plain is written except the picker's working copy, deleted right after. Old plain photos are encrypted once (`PhotoMigrationController`, flag `photos_encrypted_v1`): write the encrypted copy, update the record, then delete the plain file.
- Lost camera photo: before the camera opens, the form saves a `PhotoDraft` (settings `photo_draft`, `awaitingCamera: true`). On start, `PhotoRecovery` calls `ImagePicker.retrieveLostData()`; a returned file goes through the same encrypt-and-save path and `HomeShell` reopens the form with the draft and photo.
- Backups: `BackupBundleService` exports every table (incl. capital and stock ledgers, recipes, orders) plus photos (decrypted, base64) into one JSON encrypted with a backup password (`BackupCrypto`: PBKDF2-HMAC-SHA256 600k -> AES-256-GCM). Restore: decrypt, `BackupService.parse` validates, photos are re-encrypted into a staging folder, the database is replaced or merged (`_BackupMerge` re-points every link) in one transaction, and only then are photos moved into place.

## App updates (APK shared directly)

- `core/app_update_config.dart`: `githubRepository` ("OWNER/REPO", or `--dart-define=PITAKA_GITHUB_REPO=...`); the app reads `https://api.github.com/repos/OWNER/REPO/releases/latest`.
- `ReleaseFeed` downloads it (HTTPS only, 10 s timeout, 64 KB cap, no cookies or ids). `ReleaseInfo.parse` validates every field; a bad file is ignored.
- `UpdatePolicy`: compare build numbers (pubspec `+N` = Android versionCode); `minSupportedBuild` makes it "required" (no Skip, but the app keeps working). Skipped builds aren't shown again. Automatic check at most once per 24 h, only if Settings > "Check for updates" is on.
- `core/changelog.dart`: built-in notes. After an update, `HomeShell` shows "What's new" once for every build newer than `whats_new_seen_build`.
- The download opens in the browser (`url_launcher`). Android only installs it over the current app if it is signed with the same key, so users keep their data and a tampered APK can't replace the app.

## v9: Pay Later removed, loan payments, glass theme

- The `pay_later` table is dropped; unpaid items were moved to `debts` (installment, "Moved from Pay Later"). Old reminders (ids from 10,000,000) are cancelled at start-up (`NotificationService.cancelRetiredReminders`). A `pay_later` table inside an old backup is ignored.
- Loans: "Paid" asks Cash or an e-wallet. `TransactionRepository.markLoanPaid` saves a payment expense (`loan_payment_of_id` = the loan) on that account and sets `loan_paid_at` / `loan_paid_method`, in one SQLite transaction, so the money leaves the account and counts in the budget. `markLoanUnpaid` deletes it again. `loans()` leaves payments out.
- Orders: status `delivered_unpaid` is mapped to `delivered` (migration, restore, and `OrderStatus.fromDb`).
- Budget: `monthSummaryProvider` lays transactions still being saved over the database rows, so "Left to spend" changes the moment one is added, edited or deleted; `spentByAccount` feeds the "Paid with" line on Home.
- "Clear history" (`BackupService.clearHistory`) deletes every transaction without moving balances; capital history and "added to budget" orders are kept.
- Updates: `GitHubReleaseFeed` + `ReleaseInfo.parseGitHub` + `AppVersion` (SemVer, leading "v" ignored). `UpdateService.checkNow` never throws and returns up to date / available / error. "What's new" compares the installed version name with `whats_new_seen_version`, saved before the sheet opens.
- Glass theme (replaced by the Pitaka design system, see above): `glass.dart` and the gradient page background were removed. Tabs still switch with `FadeIndexedStack` (fade + slight slide, 300 ms, state kept).
