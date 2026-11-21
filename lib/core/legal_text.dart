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
  ];

  static const privacyPolicy = '''
Privacy Policy
Effective date: $effectiveDate

1. Summary
Pitaka is an offline budgeting app. All of your data is stored only on this device in a local database. The app has no user accounts, no login, no analytics, no ads, and no server. Your data is never uploaded or sent to us or to anyone else.

2. What the app stores
On this device only: the cards you add (a nickname, the last 4 digits, card type and color), your transactions, categories, keyword rules, debts and payments, budgets, SMS patterns, and app settings. The app never asks for or stores full card numbers, CVV codes, bank passwords or PINs to your bank.

3. SMS access (Android, optional)
SMS access is off by default. If you turn on "Import from SMS" and grant permission, the app reads messages in your inbox on the device to find bank and card transaction alerts using the patterns shown in Settings. Messages are processed only on your phone. They are not uploaded, stored as a copy, or shared. Only the transactions you review and approve are saved. Messages that look like one-time passwords (OTPs) are skipped. You can revoke the permission at any time in your phone's settings.

4. Notifications
Budget alerts and debt reminders are local notifications created by the app on your phone. No push service is used.

5. App lock
If you set a PIN, only a salted hash of it is stored on the device. Fingerprint or face unlock is handled by your phone's operating system; the app never receives your biometric data.

6. Backups and exports
When you export a CSV or JSON file or create a backup, the file is saved where you choose (for example, your Downloads folder or a cloud drive you pick). Anything you do with that file afterwards is up to you and the service you saved it to.
On Android, the app opts out of automatic cloud backup of its data. On iPhone, your own device backup (iCloud or computer backup) may include the app's data, as it does for most apps; that backup is controlled by you and Apple, not by this app.

7. Deleting your data
Use Settings > Delete all data, or uninstall the app. Because nothing is stored anywhere else, this removes your data permanently. We cannot recover it for you.

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

6. Third parties
The app does not connect to your bank. Any future feature that does will have its own terms and an updated privacy policy that you must accept first.

7. Changes
These terms may be updated. The app will ask you to accept the new version before you continue.
''';
}
