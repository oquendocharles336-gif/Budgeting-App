# Update 4: optimistic saves everywhere, stock ledger, capital withdrawals, encrypted photos

`flutter analyze` and `flutter test` were **not** run (no Flutter SDK or pub.dev access where this was made). Run first:

```bash
flutter pub get && flutter analyze && flutter test
```

- DB migration **v8** (new tables `op_keys`, `stock_movements`, `product_ingredients`; new columns `transactions.from_capital`, `orders.cancelled_at`; `capital_entries` rebuilt to allow history rows). Existing stock becomes a "Starting stock" ledger row.
- No new packages, no AndroidManifest change, minSdk stays 24. Terms version 4 (privacy text changed).
- There was no delivery fee in the code, so nothing to remove; order total = sum of items.

## Manual tests (real Android phone)
1. **Optimistic + Try again:** turn on airplane mode is not enough (offline app), so to force a failure temporarily throw in a repository method while debugging. Add a Pay Later item / transfer with fee / capital move / inventory item / product / order: the row and "Saved" appear at once; on failure the row disappears and "Try again" saves it once.
2. **Double tap:** tap Save twice quickly, and press "Try again" after a write that actually succeeded: still one row, one expense, one transfer.
3. **Stock:** Product "Cake" with recipe Sugar 50 g, Eggs 2 pcs. Order 3 cakes → Sugar -150 g, Eggs -6. Mark it Paid / Delivered → stock unchanged. Edit to 1 cake → history shows the return and the new use. Cancel → stock back. Order more than in stock → warning lists the missing items; "Add anyway" → stock 0, not negative.
4. **Capital:** add 1,000; withdraw 300 with fee 10 to GCash → GCash +300, capital 690. Withdraw 2,000 → error before saving. "Add to Budget" on sales → history shows "Sales added", capital unchanged.
5. **Photos:** take a photo; check `/data/data/<app>/app_flutter/business_photos/` has only `.enc` files (adb, debug build). Update from v7 with plain photos → "Encrypting photos… n of m", originals gone.
6. **Lost camera photo:** Developer options → "Don't keep activities" ON. Open an inventory item, type a name, tap Camera, take the photo, confirm. The app restarts; unlock → the item form reopens with the name and photo. Also try cancelling in the camera (form comes back, "No photo was taken").
7. **Backup:** Settings → Backup & restore → create (password 8+ chars). Restore with a wrong password (refused), then Replace and Merge. Photos come back. Interrupt nothing is half-restored: a damaged file changes nothing.
8. **Delete all my data:** photos folder and the photo key are gone (new photos get a new key).

---

# Update 3: Pay Later, Loans, transfer fees, business side

`flutter analyze` and `flutter test` were **not** run (no Flutter SDK or pub.dev access where this was made). Run first:

```bash
flutter pub get && flutter analyze && flutter test
```

New dependencies: `image_picker ^1.2.4`, `path_provider ^2.1.6` (was already a transitive dependency). New assets folder: `assets/qr/` (placeholder PNGs; replace with your own QR images, same names).

DB migration v7 (columns + new tables only). Terms version bumped to 3, so the accept screen shows once again.

## Manual tests
1. **Pay Later:** add an item due in 5 days → "Due in 5 days", total unpaid updates, nothing in Budget. Tap Paid → pick an account → one expense appears in Activity and the account goes down. Tap Paid fast twice / Undo / Paid again → still one expense.
2. **Loans:** add an expense in "Loan" → it shows in Loans. Paid → row shows "Paid <date>", no extra expense; Undo restores it.
3. **Transfer fee:** transfer 1,000 GCash → BPI with fee 15. The confirm dialog lists -1,015 / +1,000 / fee. After saving: GCash -1,015, BPI +1,000, a 15 "Fees" expense. Delete the transfer → the fee goes too.
4. **Business:** Home → Business. Add capital 500 from Cash with fee 10 → Cash -510, capital +500. Add inventory with a camera photo; deny camera permission in phone settings → message, form still works. Products → Orders: total 120, cash 500 → "Change to give ₱380". Enter 100 → partial-payment prompt. QR methods show the placeholder.
5. **Sales:** tiles, chart (Day/Week/Month), best sellers, methods. Add to Budget → income appears once; press again → "Nothing new to add". Unpaid orders are never added.
6. **Insights:** previous button is greyed out at the first month with spending; swiping and the month picker stop there too.
7. **Delete all my data:** business rows and the photos folder are gone.

---

# Update 2: UX, theme, analytics and debts

As before, `flutter analyze` and `flutter test` could **not** be run here (no Flutter SDK and no pub.dev access). The code was checked by reading it only. Run these on your machine first:

```bash
flutter pub get && flutter analyze && flutter test
```

**No new dependencies.** Everything uses Flutter's own animation and physics libraries.

## 1. List cascade
- **New:** `lib/presentation/widgets/motion/cascade.dart`
- **Used in:** `transactions_screen.dart`, `debts_screen.dart`, `budget_screen.dart` (category rows), `settings/categories_screen.dart`
- **Tab shell:** `home_shell.dart` now builds each tab the first time you open it, so its cascade plays when you actually see it.

## 2. Card / e-wallet swipe deck
- **New:** `lib/presentation/widgets/motion/swipe_card_deck.dart`
- **Wallets tab:** `cards/cards_screen.dart` shows the deck, with actions for the top card underneath.

## 3. Data prep
- **New:** `lib/domain/analytics/data_prep.dart`
- **Data access:** `transaction_repository.dart` gains `rawBetween`.
- **Where it runs:** `data_providers.dart` (Budget, Insights, history) and `budget_alert_service.dart`.
- **Inline summary:** `analytics_screen.dart` shows a line such as "Checked 120 transactions · removed 6 duplicates".
- **Tests:** `test/domain/data_prep_test.dart`

## 3B. Debts and reminders
- **Database:** migration v6 in `migrations.dart`, plus a "Debt" category in `default_data.dart` (also added back on restore and on "Delete all data" in `backup_service.dart`).
- **Models and repositories:** `debt.dart` (`isNew`), `transaction_entry.dart` (`debtId`), `category.dart` (`CategoryRole.debt`), `debt_repository.dart` (debt + expense saved in one SQLite transaction), `category_repository.dart`.
- **New:** `lib/domain/debt/debt_reminder.dart`
- **Rewritten:** `debt_service.dart`
- **Notifications:** `notification_service.dart` (one reminder, deadline minus 2 days, shown right away when the deadline is close).
- **Screens:**
  - `debt_form_screen.dart`: New/Existing choice, and a short explanation before asking for notification permission.
  - `debt_detail_screen.dart`: asks whether to keep or remove the linked expense when you delete a debt.
  - `debts_screen.dart`: inline "Due in 2 days" label.
  - `transaction_form_screen.dart`: note on a debt's expense.
- **Restart:** `app.dart` re-creates reminders on each unlock.
- **Tests:** `test/domain/debt_reminder_test.dart`, `test/domain/debt_service_test.dart`

## 4. Theme 60/30/10
- **New:** `lib/presentation/theme/app_palette.dart` (the tokens).
- **Rewritten:** `app_theme.dart`
- **Default theme:** `app_state_providers.dart` now defaults to Midnight.
- **Hard-coded colors removed from:**
  - Hero cards in `dashboard_screen.dart`, `debts_screen.dart` and `legal_gate_screen.dart`
  - `common.dart`, `color_picker.dart`, `rules_screen.dart`, `cards_screen.dart`
- **Splash colors:** updated in `values/colors.xml` and `pubspec.yaml`.
- **Tests:** `test/presentation/theme_contrast_test.dart` checks AA contrast for every palette.

## 5. Animated icons
- **New:** `lib/presentation/widgets/motion/animated_icons.dart`
- **Search ↔ X:** Activity
- **Lock:** lock screens, and "Lock now" in Settings
- **+ ↔ ×:** the center button
- **Menu ↔ X:** Activity filters
- **Check:** the "Saved" message and the import steps

## 6. UX principles
- **Peek:** the Home card strip and the Wallets deck show part of the next card.
- **Dim background:** handled by the theme scrim.
- **No banners:** the Home budget banner is now an inline line in the hero card.
- **Optimistic UI:**
  - `optimistic_providers.dart` (new) and `data_providers.dart`
  - `transaction_form_screen.dart`: shows "Saved" first; if the write fails, rolls back and offers "Try again".
  - `budget_screen.dart`: same for budget amounts.
- **Skeletons:** `motion/skeleton.dart` (new); `LoadingView` now draws skeleton rows. `main.dart` shows the logo instead of a spinner.
- **Prefetch:** `home_shell.dart`, plus the adjacent month on Budget and Insights.
- **Busy states:**
  - `work_steps.dart` (new): CSV import shows "Read 120 rows ✓ · Cleaned… · Checked duplicates: 6 found".
  - Insights shows the prep summary.

## Not done, or done differently
- **Duplicates:** identical transactions that were *all typed by hand* are kept (two coffees on one day are real). Only groups that include an imported copy are de-duplicated. Set `keepManualRepeats: false` to remove all of them.
- **Dark mode:** only the default **Midnight** theme is exactly midnight black / electric blue / sunset orange. The other color choices keep their own hue in the same 60/30/10 structure.
- **Optimistic UI** covers adding/editing transactions and budget amounts. Borrowing income (which also creates a debt), debts and deletes still wait for the database.
- **Busy states** were added to CSV import and Insights. SMS import still shows the old progress.
- **Cascade** covers transactions, debts, budget categories and categories. Other lists (Settings, rules, SMS patterns) are unchanged.
- **iOS** still has no `ios/` folder, so nothing for iOS notifications or theming was tested.
- **Untested on a device:** the 60 fps animation performance and the light/dark rendering. Neither could be checked without Flutter.

## Manual tests
1. **Lists:** open Activity, Budget, Debts and Categories. Rows should cascade in once. Scrolling, pull-to-refresh and coming back to the tab should not replay it. With *Remove animations* on (Android accessibility), rows should appear at once.
2. **Wallets:**
   - With 3 or more accounts, drag the top card. It should tilt and follow your finger.
   - A short drag should spring back. A long drag or a quick flick should fly off.
   - The next card should rise from behind. Tap the card to open its details.
3. **Insights:** import the same CSV twice. Totals should not double, and the line should say "removed N duplicates".
4. **Debts:**
   - Add a **New** debt. A "Debt" expense should appear in Activity, Budget and Insights.
   - Edit the amount. The expense should follow.
   - Delete the debt. You should be asked Keep/Remove.
   - Add an **Existing** debt. No expense should appear.
   - Record a payment. The remaining amount should drop and no expense should be added.
5. **Reminders:**
   - Add a deadline 5 days out. The reminder should be scheduled for deadline − 2 days at 9:00 (check with a test date).
   - A deadline tomorrow should notify right away.
   - Mark the debt paid. The reminder should be cancelled.
   - Reboot the phone. A pending reminder should still fire.
6. **Theme:** switch Light/Dark and each color in Settings. Backgrounds should be the main color, cards the second color, and buttons/FAB/key numbers the accent. Text should stay readable everywhere.
7. **Icons:**
   - Activity search: the icon should morph to X and back.
   - Filters: menu ↔ X.
   - "+": turns into × while the form is open.
   - Settings → Lock now: the padlock closes.
   - Lock screen: the shackle opens while checking and closes on failure.
8. **Optimistic save:**
   - Add an expense. The form should close at once, the row should show immediately, and "Saved" should appear with a check.
   - To test failure, put the phone in a state where the write fails (or briefly make `insert` throw while debugging). The row should disappear and "Try again" should reopen the form with your values.
9. **Skeletons:** on a slow device, or with a large database, loading should show grey layout blocks, not spinners.

---

# Changes: security setup, back button, balances, branding

`flutter analyze` and `flutter test` were **not** run. The environment used to make these changes had no Flutter SDK and couldn't reach pub.dev. Run these first:

```bash
flutter pub get
flutter analyze
flutter test
dart run flutter_launcher_icons        # optional: icons are already generated
dart run flutter_native_splash:create  # optional: splash is already generated
```

New dev dependencies: `flutter_launcher_icons ^0.14.4`, `flutter_native_splash ^2.4.6`.
No new runtime dependencies: `local_auth`, `flutter_secure_storage`, `crypto` and `cryptography` were already in the project.

## 1. First-launch security setup

| File | Change |
|---|---|
| `lib/domain/services/app_lock_service.dart` | Adds `UnlockMethod` (device/pin). Adds `authenticateDevice()` with `biometricOnly: false`, which maps every `LocalAuthExceptionCode` to a clear message. Stores the device key and the method in secure storage. Adds a wrong-PIN counter that persists across restarts (`PinAttempts`). Adds `LockGuard`, which stops the app from locking during file pickers and system prompts. |
| `lib/domain/security/vault.dart` | Accepts a 6–12 digit PIN (rejects 000000 and 123456-style PINs) or an 8+ character password. Adds `prepareWithoutPassword`, `hasPassword`, `setPassword`, `removePassword` and `replaceRecoveryKeyWith`. |
| `lib/main.dart` | Adds new stages: choose method → device lock screen or PIN login. If the phone lock was removed, the app asks for an in-app PIN. When the recovery key is used, the app switches to PIN. |
| `lib/app.dart` | The app locks as soon as it goes to the background. A logo cover shows while the app is inactive. Locking is suspended for up to 2 minutes during guarded actions. |
| `lib/presentation/screens/auth/security_setup_screen.dart` (new) | Lets the user choose a method. The phone-lock option only appears when `isDeviceSupported()` is true. |
| `lib/presentation/screens/auth/device_lock_screen.dart` (new) | Prompts automatically. Lets the user retry. Shows error messages. Links to the recovery key. |
| `sign_up_screen.dart`, `login_screen.dart`, `forgot_password_screen.dart`, `auth_widgets.dart`, `recovery_key_screen.dart`, `settings/change_password_screen.dart` | Wording changed to "PIN or password". Adds a PIN/password toggle, the logo, and a configurable title. The wrong-PIN counter now persists. |
| `lib/presentation/screens/settings/settings_screen.dart` | Adds an "Unlock method" switcher. Hides "Change PIN" and the fingerprint toggle in phone-lock mode. In phone-lock mode, the recovery key and backup password work without an app PIN. Pickers are guarded. |
| `csv_import_screen.dart`, `sms_import_screen.dart`, `debt_form_screen.dart`, `budget_screen.dart` | Pickers and permission prompts are wrapped in `LockGuard.run`. |

Android: `USE_BIOMETRIC`, `FlutterFragmentActivity` and `minSdk 24` were already in place, so nothing needed to change there.
iOS: the project has no `ios/` folder. See docs/ARCHITECTURE.md → Branding for the `Info.plist` keys to add after `flutter create --platforms=ios .`.

## 2. Back button

`lib/presentation/screens/home_shell.dart` uses `PopScope` with a tab history stack:
- Back returns to the previous tab, or to Home if there's no history.
- On Home, back shows the "Exit app?" dialog.
- Pushed screens still pop first.

The shell also gets a **Wallets** tab. The tabs are now Home, Activity, Budget and Wallets. Insights moved to a quick action on Home, replacing "Cards".

## 3. Balances

| File | Change |
|---|---|
| `lib/data/db/migrations.dart` | v5 adds `cards.balance` and `transactions.affects_balance` through `ALTER TABLE` in `onUpgrade`, so no data is lost. |
| `lib/data/repositories/account_ledger.dart` (new) | Holds the balance math. The Cash balance is stored in settings (`cash_balance`). |
| `transaction_repository.dart`, `card_repository.dart` | Insert, update and delete write the row and the balance inside one SQLite transaction. Deleting an account undoes its transfers. |
| `transaction_entry.dart`, `payment_card.dart` | Add the `affectsBalance` and `balance` fields. |
| `transaction_import_service.dart` | Only manual entries move balances. |
| `transaction_service.dart` | `availableBefore()` supports the "Insufficient balance" check. |
| `backup_service.dart` | "Delete all data" also resets the Cash balance. |
| `data_providers.dart` | Adds `cashBalanceProvider` and `balanceSummaryProvider`. |
| `cards_screen.dart`, `card_form_screen.dart`, `card_detail_screen.dart` | Wallets tab: total card, Cash tile, balances, "Edit balance" and delete. The add/edit form has a starting balance field. |
| `transaction_form_screen.dart` | The source picker shows balances. A confirmation appears when an amount exceeds the source's balance. |
| `widgets/available_balance_card.dart` (new), `dashboard_screen.dart`, `budget_screen.dart` | Show the available balance. The Budget tab also shows the month's income. |

Design notes:
- The existing `cards` table already served as the accounts table, and `card_id` already acted as `account_id`, so they were extended instead of duplicated.
- Imports don't move balances, because the starting balance the user types already includes them.
- Income raises the **available balance**. Monthly spending limits are not changed.

## 4. Branding

- `assets/logo/logo.svg` and `logo.png`: a wallet with a peso coin in the app's indigo.
- `logo_foreground.png` and `splash_android12.png`.
- Android launcher icons, adaptive icon, splash screens for light/dark and Android 12+, and the Windows `.ico` were all generated from these.
- `pubspec.yaml`: registers `assets/logo/` and adds the generator configs.

To use your own logo, replace these files:
- `assets/logo/logo.png`
- `assets/logo/logo_foreground.png`
- `assets/logo/splash_android12.png`

Optionally replace `logo.svg` too. Then run the two `dart run` commands above.

## Tests added

- `test/domain/account_ledger_test.dart`
- New cases in `test/domain/vault_test.dart`

## Manual test steps

**Security**
1. Fresh install on a phone with a screen lock. You should see "Secure Pitaka" with two options.
2. Choose phone lock and confirm. You should see the recovery key, then the app.
3. Background the app and return. The lock screen should show and prompt automatically.
4. Cancel the prompt. You should see "Unlock was canceled" and a working Unlock button.
5. Fail many times. You should see the "Too many attempts" message.
6. Remove the phone's screen lock and reopen the app. You should be asked to set an in-app PIN, and your data should still be there.
7. Fresh install on a phone with no lock. Only the PIN option should appear.
8. Try PIN 123456. It should be refused.
9. Enter two different PINs. You should see "don't match".
10. Enter the wrong PIN 5 times. You should have to wait 30 s, and the wait should continue after killing the app.
11. In Settings → Unlock method, switch both ways. Lock and unlock each time.
12. Test the recovery key: "Can't unlock?" → reset. The app should switch to PIN.
13. Pick a CSV or backup file. The app should not lock while the picker is open.

**Back button**
1. Go Home → Budget → Wallets, then press back twice. You should land on Budget, then Home.
2. Press back on Home. You should see the "Exit app?" dialog. Cancel should stay; Exit should close the app.
3. Open "+" and press back. The form should close and the tab should stay the same.
4. On Budget with no history, press back. You should land on Home.

**Balances**
1. Upgrade from an old build. Existing data should be kept and balances should be 0.
2. In Wallets, add GCash with ₱1,000.
3. Add an expense of ₱300 paid with GCash. The balance should be ₱700, and Home, Budget and Wallets should all update.
4. Add an expense of ₱900 from GCash. You should see the "Insufficient balance" dialog. Cancel should not save; Save anyway should leave −₱200.
5. Add income of ₱5,000 to Cash. Cash and the available balance should both go up.
6. Edit an expense's amount or account. The old account should be refunded and the new one charged.
7. Delete the expense. The money should go back.
8. Transfer Cash → GCash. Both balances should move.
9. Delete GCash. The transfer should be undone on Cash.
10. Try empty, letters or negative values in amount/balance fields. They should be refused.

**Branding**
1. The launcher icon should show on an Android 8+ adaptive icon and on older versions.
2. The splash should match in light and dark, and on Android 12+.
3. The logo should appear on the setup, lock and PIN screens.
4. The label under the icon should be "Pitaka".
