/// Privacy Policy and Terms shown in the app.
///
/// IMPORTANT: If bank sync (or any feature that sends data off the device)
/// is ever added, this policy MUST be rewritten before release, and
/// `currentTermsVersion` bumped so users accept the new version.
class LegalText {
  LegalText._();

  static const effectiveDate = 'November 25, 2026';

  static const privacySummary = [
    'Everything you enter stays on this phone, in a local encrypted SQLite database. There is no online account, no sign-up and no cloud server.',
    'Your PIN, password or phone lock only unlocks the app on this phone. It is not an account and is never sent anywhere.',
    'The only internet use is the optional update check and update download. They send nothing about you.',
    'No data is collected. We never upload, sell or share your transactions, cards, e-wallets, debts, loans, budgets or business records.',
    'SMS reading is off unless you turn it on. If you do, alerts are read on your phone only to find transactions.',
    'Backups and exports go only where you choose to save them.',
    'Photos you add to business items are encrypted and stay in the app\'s private folder on this phone.',
  ];

  static const privacyPolicy = '''
Privacy Policy
Effective date: $effectiveDate

1. Summary
Pitaka is an offline-first budgeting app. All of your data is stored only on this device, in a local SQLite database that is encrypted. There is no online account and no sign-up, no analytics, no ads, no tracking, and no server that receives your data. We do not collect any data, so we have nothing to sell or share. Its only internet use is the optional update check and update download described below. The PIN, password or phone lock you choose only unlocks the app and its encrypted data on this phone; it is not an online login. Your data is never uploaded or sent to us or to anyone else.

2. What the app stores
On this device only: your Cash amount; the cards and e-wallets you add (a nickname, the last 4 digits or the e-wallet mobile number, type, color and the balance you enter); your transactions, categories, keyword rules, debts, loans and payments, budgets, SMS patterns, and app settings (such as light or dark mode, accent color, currency and whether Business Mode is on). If you use the business side, also: business capital entries, inventory items, products, and orders (including the buyer names you type). The app never asks for or stores full card numbers, CVV codes, bank passwords or PINs to your bank.

2a. Cards, e-wallets and your available balance
The balance of a card or e-wallet is a number you type and keep up to date; transactions you record add to it or take from it. The app does not connect to your bank, card issuer or e-wallet (for example GCash or Maya) and cannot see your real balance or move money. Available balance is your Cash plus your debit, prepaid and e-wallet balances, worked out on this phone. Credit cards are shown separately as available credit.

2b. Business Mode
Business Mode is a switch in Settings that only shows or hides the Business buttons on Home and the Business tab. Turning it off hides them; it does not delete any business records, which stay on this phone until you delete them.

3. SMS access (Android, optional)
SMS access is off by default. If you turn on "Import from SMS" and grant permission, the app reads messages in your inbox on the device to find bank and card transaction alerts using the patterns shown in Settings. Messages are processed only on your phone. They are not uploaded, stored as a copy, or shared. Only the transactions you review and approve are saved. Messages that look like one-time passwords (OTPs) are skipped. You can revoke the permission at any time in your phone's settings.

4. Notifications
Budget alerts and debt reminders are local notifications created by the app on your phone. No push service is used.

4d. Phone permissions
Pitaka asks your phone for only three things, each with an "Allow" button you choose to tap (Settings > Phone permissions): notifications (alerts and reminders), reading SMS (only for Import from SMS) and installing its own updates. Tapping Allow shows Android's own question or opens Android's settings page for Pitaka; you can change any of them there at any time. The app keeps working without them.

4a. Photos (optional)
You can add a photo to an inventory item or product, from the camera or your gallery. The app opens your phone's own camera or photo picker; on Android it does not ask for camera or storage permission itself. Only the photo you choose is copied, made smaller, encrypted (AES-256-GCM) and saved in the app's private folder on this phone. The photo key is kept in Android's secure key storage (Android Keystore), never in the database or plain app settings. The picker's temporary unencrypted copy is deleted right after encryption, and photos are decrypted only in memory to show them. Photo location data is not kept. Removing a photo, deleting the item, or using "Delete all my data" deletes the file; "Delete all my data" also deletes the photo key. If Android closes the app while the camera is open, the form you were filling in is kept on this phone (in the encrypted database) so the photo can be attached when you return.

4b. Payment QR codes
The QR images shown for Maya, MariBank and BDO are pictures you add to the app. The app does not connect to these services, does not process or check payments, and sends nothing to them.

4c. Update check and download (optional)
Once a day, if "Check for updates" is on (Settings > App updates), and whenever you tap "Check now", the app reads the public "latest release" information of the app's GitHub repository to see whether a newer version exists and what changed. If you choose to update, the app downloads the new installer file (APK) from that release, checks that it is complete and unchanged (SHA-256), and hands it to Android's own installer, which asks you to confirm. These requests contain no account, device ID, budget data or other personal information; like any web request, GitHub can see your phone's IP address and the time of the request. You can turn the automatic check off at any time; the app works fully without it.

4f. Fonts and open-source components
The app's typeface (Plus Jakarta Sans) and its other open-source components are built into the app. Nothing is downloaded to show them, and no request is made to a font or content service. Their licenses are listed in Settings > Legal > Open-source licenses.

5. Password and encryption
Your data is stored in an encrypted database (SQLCipher, AES-256). The key that unlocks it is protected by your password and by a recovery key that is shown to you once. Neither your password nor your recovery key is stored, and nothing is sent anywhere, so we cannot see your data or reset your password. If you lose both your password and your recovery key, your data cannot be recovered by anyone.
If you turn on fingerprint or face unlock, the database key is kept in your phone's secure storage (Android Keystore or iOS Keychain). The fingerprint or face check is handled by your phone's operating system; the app never receives your biometric data.

6. Backups and exports
Full backups are one file with your data and your business photos, encrypted with a backup password you choose (PBKDF2 key derivation, AES-256-GCM). Photos are stored inside the backup file so it can be restored on another phone; they are protected by the backup password, not by this phone's photo key. CSV exports are not encrypted. When you export a file or create a backup, the file is saved where you choose (for example, your Downloads folder or a cloud drive you pick). Anything you do with that file afterwards is up to you and the service you saved it to.
On Android, the app opts out of automatic cloud backup of its data. On iPhone, your own device backup (iCloud or computer backup) may include the app's data, as it does for most apps; that backup is controlled by you and Apple, not by this app.

7. Deleting your data
Use Settings > Delete all my data, or uninstall the app. This removes your personal and business data and the photos you added. Because nothing is stored anywhere else, this removes your data permanently. We cannot recover it for you.

8. Children
The app does not knowingly collect information from anyone, including children, because it does not collect information at all.

9. Changes
If this policy changes, the app will show the new version and ask you to accept it before you continue.

10. Contact
For questions, contact the app's developer through the store listing.
''';

  static const terms = '''
Terms & Conditions
Effective date: $effectiveDate

1. Using the app
Pitaka is a personal, offline-first tool for tracking your own spending, budgets, cards and e-wallets, debts and loans. There is no online account or sign-up: the PIN, password or phone lock only unlocks the app on your phone. By using it, you agree to these terms.

2. Your data, your responsibility
Your data is stored only on your device, in a local encrypted SQLite database. The developer does not collect, receive, sell or share it. You are responsible for keeping your phone secure and for making backups. If your phone is lost, reset or the app is uninstalled without a backup, your data cannot be recovered.

2a. Balances you enter
Cash, card and e-wallet balances are the amounts you type and the transactions you record. They can differ from your real bank, card or e-wallet balance. Always rely on your bank, card issuer or e-wallet app for the actual amount.

3. Not financial advice
The app shows totals, charts and budget alerts based on what you enter or import. It does not give financial, legal or tax advice. Always check important figures against your official bank and card statements.

4. Accuracy of imports
CSV and SMS imports depend on the file format and message wording of your bank. Parsed amounts, dates or merchants may be wrong. You agree to review imported items before saving them.

4a. Loans and your budget
Loans are transactions in the "Loan" category. A loan you gave counts as spending in the month you lent it. If you mark it paid back in that same month, it is taken out of that month's spending; if it is paid back in a later month, it stays counted in the month you lent it. Marking a loan unpaid again reverses this. The amounts, dates and payment accounts are the ones you enter, and the app does not contact the person you lent to or check that you were paid.

5. No warranty
The app is provided "as is", without warranties of any kind. To the extent allowed by law, the developer is not liable for any loss arising from use of the app, including missed payments or inaccurate figures.

5a. Business features and Business Mode
Business Mode only shows or hides the Business buttons and tab; it never deletes business records. Capital, inventory, orders and sales analytics are a simple record of what you type. They are not accounting, inventory-valuation or tax software, and they don't replace official receipts or records you may need to keep. When a buyer pays by QR, check the payment in your own Maya, MariBank or BDO app; this app does not verify payments.

6. Third parties
The app does not connect to your bank or to any payment service. Any future feature that does will have its own terms and an updated privacy policy that you must accept first.

7. Open-source components
The app includes open-source software and the Plus Jakarta Sans typeface (SIL Open Font License 1.1). These are used under their own licenses, listed in Settings > Legal > Open-source licenses; nothing in these terms limits your rights under those licenses.

8. Changes
These terms may be updated. The app will ask you to accept the new version before you continue.
''';
}
