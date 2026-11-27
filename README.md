# Pitaka — offline budget & expense tracker

Flutter app (Android first; iOS possible, see below) for tracking card, e-wallet and cash spending, monthly
budgets, debts and loans, with an optional Business Mode. No backend and no online account. All data is stored
on the phone in an encrypted SQLite database, protected by a PIN/password you set on the device.

- Architecture overview: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Publishing a new version: [docs/RELEASING.md](docs/RELEASING.md)
- Version history and manual test lists: [CHANGES.md](CHANGES.md)

## Features

- Cards, e-wallets and cash (nickname, last 4 digits, type, color); one transaction list with search and filters
- Available balance shown as two boxes: Cash, and Cards & e-wallets
- Imports: CSV statements (column mapping + preview) and Android SMS alerts (opt-in, reviewed before saving)
- Auto-categorization with editable keyword rules; duplicate detection on every import
- Monthly budget + per-category budgets, 80% / 100% alerts (notification + banner), history of past months
- Debts with payments, remaining balance, due-date reminders; Loans you gave, with repayment going back to Cash or an e-wallet
- Home badges showing how many debts and loans are still open; swipe left/right to move between tabs
- Business Mode (Settings → Business Mode): orders, sales, products, inventory and capital. Off by default; turning it off hides it but keeps your records
- Analytics: daily chart, category donut, weekly and monthly comparison, average per day
- Light/dark/system theme and accent color; currency (default ₱ PHP)
- Local PIN/password that encrypts the whole database (SQLCipher) with a one-time recovery key; optional phone-lock/fingerprint/face unlock; password-encrypted backups, CSV export, delete all data
- In-app updates from GitHub Releases ("Update available", "What's new" once per update); see [docs/RELEASING.md](docs/RELEASING.md)
- "Allow" buttons for notifications, bank texts and installing updates (Home, and Settings → Phone permissions)
- Privacy Policy and Terms shown on first launch with an "I agree" checkbox; shown again when the terms version changes

## Requirements

- Flutter with Dart **3.12+** (a recent stable channel)
- Android: Android Studio with **SDK Platform 37** installed (needed by `flutter_local_notifications` 23).
  If Gradle says the platform is missing, open *SDK Manager* and install it. `minSdk` is 24 (Android 7.0).

## Run it

```bash
flutter pub get
flutter analyze
flutter test          # unit tests (CSV, SMS, de-dup, budget, debts, backups, business, updates, ...)
flutter run
```

**iOS:** this project folder doesn't include an `ios/` directory (it has `android/` and `windows/`). Create it once, then add the Face ID text:

```bash
flutter create --platforms=ios .
```

In `ios/Runner/Info.plist` add:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Unlock Pitaka with Face ID</string>
```

SMS import and in-app APK install are Android-only.

### Try it with sample data

- *Settings → Load sample data* adds 3 cards, ~2 months of transactions, budgets and 2 debts.
- Sample CSV files: `assets/sample/sample_statement.csv` and `assets/sample/sample_debit_credit.csv`.
  Copy one to the phone (e.g. `adb push assets/sample/sample_statement.csv /sdcard/Download/`), then
  *Import → CSV statement*. Import the same file twice to see duplicates skipped.
- Sample SMS texts for the pattern tester: `assets/sample/sample_sms.txt`.

## Build the APK

```bash
flutter build apk --release          # build/app/outputs/flutter-apk/Pitaka.apk
flutter build appbundle --release    # for Google Play
```

The APK to install and share is **`Pitaka.apk`**. A Gradle task (`pitakaApk` in `android/app/build.gradle.kts`)
copies it from `app-release.apk` right after the build; `app-release.apk` stays next to it because the Flutter
tool needs that exact name. With `--split-per-abi` you get `Pitaka-arm64-v8a.apk`, `Pitaka-armeabi-v7a.apk`, etc.

To change the name shown on the phone, edit `android:label` in `android/app/src/main/AndroidManifest.xml`
(and `title:` in `lib/app.dart`). Don't change `applicationId` unless you want Android to treat it as a different app.

The release build is signed with the debug key so it installs right away. Before publishing, create an
upload key and a `signingConfig` (see https://docs.flutter.dev/deployment/android#sign-the-app).
Once you share APKs, **always use the same key**: Android only installs an update over an existing install
(keeping the user's data) when the signature matches.

**Google Play and SMS:** Play restricts `READ_SMS`. "SMS-based money management" is a listed exception,
but you must submit the Permissions Declaration Form and pass review. If you'd rather skip that, remove the
`READ_SMS` line from `android/app/src/main/AndroidManifest.xml`. The app still works; the SMS option will
just show "permission not given".

## Project structure

```
lib/
  main.dart, app.dart
  core/            money (centavos), dates, text normalize, legal text, feature flags,
                   update config (GitHub repo), in-app changelog
  data/
    db/            app_database, migrations, default_data, seed_data
    models/        PaymentCard, TransactionEntry, Category/CategoryRule, Debt/DebtPayment,
                   Budget, SmsPattern, RawTransaction
    repositories/  one per table group; all SQL lives here
    sources/       TransactionSource + Manual, CSV, SMS, BankSync (stub), SMS inbox channel,
                   release feed + APK updater, phone permissions, photo store
  domain/
    csv/ sms/ import/ budget/ analytics/ debt/ business/ transfer/ security/ update/   pure logic (unit-tested)
    services/      transactions, debts, business, budget alerts, notifications, backup, app lock,
                   phone access, updates
  presentation/
    providers/     Riverpod providers
    theme/         colors, typography, category icons
    widgets/       shared UI pieces
    screens/       dashboard, transactions, import, cards, debts, loans, budget, analytics, business,
                   settings, auth (login, lock, recovery), legal
test/              unit tests (domain/, core/, presentation/)
android/app/src/main/java/com/budgeting/bugeting_app/
                   MainActivity.java (SMS and permissions channels, FlutterFragmentActivity),
                   UpdateFileProvider.java (in-app update install)
assets/            logo/, qr/, sample/ (sample CSVs and SMS texts)
docs/              ARCHITECTURE.md, RELEASING.md
```

## Database schema & migrations

Schema is in `lib/data/db/migrations.dart` (tables, foreign keys, indexes). To change it:

1. Add a new function, e.g. `_v13AddTags`, with the `ALTER TABLE` / `CREATE TABLE` statements
   (the current latest version is 12: monthly debt due day, utility categories, order
   fulfillment, e-wallet auto-tracking).
2. Register it: `13: _v13AddTags` in `_steps`. `latestVersion` updates automatically.
3. Never edit a step that has already shipped.
4. If the change affects backups, check `BackupService` (it copies whole tables).

## Adding a new TransactionSource

Example: a source that reads a bank's OFX file.

1. Create `lib/data/sources/ofx_import_source.dart`:

   ```dart
   class OfxImportSource implements TransactionSource {
     OfxImportSource(this.fileText);
     final String fileText;

     @override String get id => 'csv_import';          // or add a new TransactionSourceType
     @override String get displayName => 'OFX statement';
     @override bool get requiresNetwork => false;
     @override Future<bool> isAvailable() async => true;

     @override
     Future<List<RawTransaction>> fetchTransactions({required PaymentCard card, DateTime? since}) async {
       // Parse fileText and return RawTransaction(date, description, amount (positive centavos),
       // kind, source, cardId: card.id, externalId: <the bank's FITID>)
     }
   }
   ```

2. If it's a new kind of source, add a value to `TransactionSourceType` **and** to the `CHECK (source IN (...))`
   constraint with a new migration.
3. In a screen: `final candidates = await ref.read(importServiceProvider).preview(source, card: card);`
   then show `ImportReview(candidates: candidates)`. That's it — categorizing, de-duplication, saving,
   budget alerts and analytics already work.

Give each transaction a stable `externalId` when the source has one; it makes re-imports exact.

## Adding bank sync later

Linking real bank or card accounts needs a licensed aggregator (for example **Brankas** or **Finverse** in
the Philippines) and a small backend. The phone must never hold the aggregator's secret API keys.

```
Phone (BankSyncSource) ──HTTPS──▶ Your small backend ──▶ Aggregator API ──▶ Bank
        ▲                              │ holds API keys, stores the user's link token
        └──── normalized JSON list ◀───┘
```

How it would work:

1. **Link:** the app opens the aggregator's hosted link/consent page. The user signs in to their bank there
   (the app never sees bank passwords). The aggregator returns a token to your backend.
2. **Fetch:** `BankSyncSource.fetchTransactions(card, since)` calls your backend, e.g.
   `GET /transactions?account=<id>&since=<date>`. The backend calls the aggregator and returns a simple list:
   `[{ "id": "...", "date": "2026-11-20", "description": "...", "amount": -125000 }]`.
3. **Map:** turn each item into `RawTransaction(..., source: TransactionSourceType.bankSync,
   externalId: 'bank:<id>')` and return it. The existing pipeline does the rest.
4. **Turn it on:** implement `isAvailable()` (network + linked account), then build with
   `--dart-define=BANK_SYNC=true` to show it in the UI.

What does **not** change: the UI flow (it reuses the import review screen), the database (`source` already
allows `bank_sync`; `external_id` handles de-duplication), budgets and analytics.

What **does** change, and must be done before release:

- `INTERNET` is already in the manifest (used for the update check), so no new permission is needed for sync.
- **Rewrite the Privacy Policy** in `lib/core/legal_text.dart` (data would now leave the device, go to your
  backend and the aggregator), and bump `currentTermsVersion` in `app_state_providers.dart` (currently `'6'`) so every user
  re-accepts. The current policy promises your records never leave the phone — that would no longer be true.
- Add some form of account (the backend needs to know whose bank link it is), which also means updating
  the "no registration" promise in the onboarding text.
- Check the aggregator's current docs, pricing, and local rules (BSP / Data Privacy Act) — they change.

## Before you build or release

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

If a clean build misbehaves, run `flutter clean` and delete `android/.gradle` first (see `RUN THIS.md`).
Gradle prints warnings about `java.lang.System::load` and about plugins that use the Kotlin Gradle Plugin
(e.g. `cryptography_flutter`); they don't stop the build.

## Privacy

Your records stay on the device and are never uploaded. The only network use is the update check, which asks
GitHub's public Releases API for the latest version (no account data is sent). SMS access, if enabled, is used only to read
transaction alerts locally. If bank sync (or anything that sends data off the device) is ever added,
the Privacy Policy **must** be updated first — see above.
