# Pitaka — offline budget & expense tracker

Flutter app (Android + iOS) for tracking card and cash spending, monthly budgets, and debts.
No backend, no account, no login. All data is stored on the phone in SQLite.

Architecture overview: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Features

- Cards (nickname, last 4 digits, type, color) and cash transactions, one list with search and filters
- Imports: CSV statements (column mapping + preview) and Android SMS alerts (opt-in, reviewed before saving)
- Auto-categorization with editable keyword rules; duplicate detection on every import
- Monthly budget + per-category budgets, 80% / 100% alerts (notification + banner), history of past months
- Debts with payments, remaining balance, due-date reminders
- Analytics: daily chart, category donut, weekly and monthly comparison, average per day
- Light/dark/system theme and accent color; currency (default ₱ PHP)
- CSV/JSON export, full backup/restore, delete all data, optional PIN + fingerprint/face lock
- Privacy Policy and Terms shown on first launch with an "I agree" checkbox

## Requirements

- Flutter with Dart **3.12+** (the project was created on a recent stable channel)
- Android: Android Studio with **SDK Platform 37** installed (needed by `flutter_local_notifications` 23).
  If Gradle says the platform is missing, open *SDK Manager* and install it.

## Run it

```bash
flutter pub get
flutter test          # unit tests (CSV, SMS, de-dup, budget, import pipeline)
flutter run
```

**iOS:** this project folder didn't include an `ios/` directory. Create it once, then add the Face ID text:

```bash
flutter create --platforms=ios .
```

In `ios/Runner/Info.plist` add:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Unlock Pitaka with Face ID</string>
```

SMS import is Android-only; everything else works on iOS.

### Try it with sample data

- *Settings → Load sample data* adds 3 cards, ~2 months of transactions, budgets and 2 debts.
- Sample CSV files: `assets/sample/sample_statement.csv` and `assets/sample/sample_debit_credit.csv`.
  Copy one to the phone (e.g. `adb push assets/sample/sample_statement.csv /sdcard/Download/`), then
  *Import → CSV statement*. Import the same file twice to see duplicates skipped.
- Sample SMS texts for the pattern tester: `assets/sample/sample_sms.txt`.

## Build the APK

```bash
flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release    # for Google Play
```

The release build is signed with the debug key so it installs right away. Before publishing, create an
upload key and a `signingConfig` (see https://docs.flutter.dev/deployment/android#sign-the-app).

**Google Play and SMS:** Play restricts `READ_SMS`. "SMS-based money management" is a listed exception,
but you must submit the Permissions Declaration Form and pass review. If you'd rather skip that, remove the
`READ_SMS` line from `android/app/src/main/AndroidManifest.xml`. The app still works; the SMS option will
just show "permission not given".

## Project structure

```
lib/
  main.dart, app.dart
  core/            money (centavos), dates, text normalize, legal text, feature flags
  data/
    db/            app_database, migrations, default_data, seed_data
    models/        PaymentCard, TransactionEntry, Category/CategoryRule, Debt/DebtPayment,
                   Budget, SmsPattern, RawTransaction
    repositories/  one per table group; all SQL lives here
    sources/       TransactionSource + Manual, CSV, SMS, BankSync (stub), SMS inbox channel
  domain/
    csv/ sms/ import/ budget/ analytics/   pure logic (unit-tested)
    services/      transactions, debts, budget alerts, notifications, backup, app lock
  presentation/
    providers/     Riverpod providers
    theme/         colors, typography, category icons
    widgets/       shared UI pieces
    screens/       dashboard, transactions, import, cards, debts, budget, analytics, settings, legal, lock
test/domain/       unit tests
android/app/src/main/java/.../MainActivity.java   SMS MethodChannel + FlutterFragmentActivity
assets/sample/     sample CSVs and SMS texts
```

## Database schema & migrations

Schema is in `lib/data/db/migrations.dart` (tables, foreign keys, indexes). To change it:

1. Add a new function, e.g. `_v3AddTags`, with the `ALTER TABLE` / `CREATE TABLE` statements.
2. Register it: `3: _v3AddTags` in `_steps`. `latestVersion` updates automatically.
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

- Add `<uses-permission android:name="android.permission.INTERNET"/>` to the main manifest.
- **Rewrite the Privacy Policy** in `lib/core/legal_text.dart` (data would now leave the device, go to your
  backend and the aggregator), and bump `currentTermsVersion` in `app_state_providers.dart` so every user
  re-accepts. The current policy promises data never leaves the phone — that would no longer be true.
- Add some form of account (the backend needs to know whose bank link it is), which also means updating
  the "no registration" promise in the onboarding text.
- Check the aggregator's current docs, pricing, and local rules (BSP / Data Privacy Act) — they change.

## Things to check on your first build

This code was written without a Flutter toolchain available, so it hasn't been compiled yet. It targets
the current major versions of each package (`flutter_riverpod` 3, `sqflite` 2.4, `fl_chart` 1.3,
`file_picker` 13, `flutter_local_notifications` 23, `local_auth` 3). If `flutter analyze` reports
something, it will most likely be a small API rename in one of those packages. Fix it in place; the
architecture doesn't depend on it.

## Privacy

All data stays on the device and is never uploaded. SMS access, if enabled, is used only to read
transaction alerts locally. If bank sync (or anything that sends data off the device) is ever added,
the Privacy Policy **must** be updated first — see above.
