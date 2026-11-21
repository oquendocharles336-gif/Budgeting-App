/// Privacy Policy and Terms shown in the app.
///
/// IMPORTANT: If bank sync (or any feature that sends data off the device)
/// is ever added, this policy MUST be rewritten before release, and
/// `currentTermsVersion` bumped so users accept the new version.
class LegalText {
  LegalText._();

  static const effectiveDate = 'November 21, 2026';

  static const privacySummary = [
    'Everything you enter stays on this phone. There is no account and no cloud server.',
    'We never upload, sell or share your transactions, cards, debts or budgets.',
    'SMS reading is off unless you turn it on. If you do, alerts are read on your phone only to find transactions.',
    'Backups and exports go only where you choose to save them.',
    'Photos you add to business items are encrypted and stay in the app\'s private folder on this phone.',
  ];

  static const privacyPolicy = '''
Privacy Policy
Effective date: $effectiveDate

1. Summary
Pitaka is an offline budgeting app. All of your data is stored only on this device in a local database. The app has no online accounts, no analytics, no ads, and no server. The password you create is a local login that encrypts your data on this phone. Your data is never uploaded or sent to us or to anyone else.

2. What the app stores
On this device only: the cards you add (a nickname, the last 4 digits, card type and color), your transactions, categories, keyword rules, debts and payments, Pay Later purchases, budgets, SMS patterns, and app settings. If you use the business side, also: business capital entries, inventory items, products, and orders (including the buyer names you type). The app never asks for or stores full card numbers, CVV codes, bank passwords or PINs to your bank.

3. SMS access (Android, optional)
SMS access is off by default. If you turn on "Import from SMS" and grant permission, the app reads messages in your inbox on the device to find bank and card transaction alerts using the patterns shown in Settings. Messages are processed only on your phone. They are not uploaded, stored as a copy, or shared. Only the transactions you review and approve are saved. Messages that look like one-time passwords (OTPs) are skipped. You can revoke the permission at any time in your phone's settings.

4. Notifications
Budget alerts, debt reminders and Pay Later reminders are local notifications created by the app on your phone. No push service is used.

4a. Photos (optional)
You can add a photo to an inventory item or product, from the camera or your gallery. The app opens your phone's own camera or photo picker; on Android it does not ask for camera or storage permission itself. Only the photo you choose is copied, made smaller, encrypted (AES-256-GCM) and saved in the app's private folder on this phone. The photo key is kept in Android's secure key storage (Android Keystore), never in the database or plain app settings. The picker's temporary unencrypted copy is deleted right after encryption, and photos are decrypted only in memory to show them. Photo location data is not kept. Removing a photo, deleting the item, or using "Delete all my data" deletes the file; "Delete all my data" also deletes the photo key. If Android closes the app while the camera is open, the form you were filling in is kept on this phone (in the encrypted database) so the photo can be attached when you return.

4b. Payment QR codes
The QR images shown for Maya, MariBank and BDO are pictures you add to the app. The app does not connect to these services, does not process or check payments, and sends nothing to them.

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
Pitaka is a personal tool for tracking your own spending, budgets and debts. By using it, you agree to these terms.

2. Your data, your responsibility
Your data is stored only on your device. You are responsible for keeping your phone secure and for making backups. If your phone is lost, reset or the app is uninstalled without a backup, your data cannot be recovered.

3. Not financial advice
The app shows totals, charts and budget alerts based on what you enter or import. It does not give financial, legal or tax advice. Always check important figures against your official bank and card statements.

4. Accuracy of imports
CSV and SMS imports depend on the file format and message wording of your bank. Parsed amounts, dates or merchants may be wrong. You agree to review imported items before saving them.

5. No warranty
The app is provided "as is", without warranties of any kind. To the extent allowed by law, the developer is not liable for any loss arising from use of the app, including missed payments or inaccurate figures.

5a. Business features
Capital, inventory, orders and sales analytics are a simple record of what you type. They are not accounting, inventory-valuation or tax software, and they don't replace official receipts or records you may need to keep. When a buyer pays by QR, check the payment in your own Maya, MariBank or BDO app; this app does not verify payments.

6. Third parties
The app does not connect to your bank or to any payment service. Any future feature that does will have its own terms and an updated privacy policy that you must accept first.

7. Changes
These terms may be updated. The app will ask you to accept the new version before you continue.
''';
}
