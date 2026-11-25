import '../domain/update/app_update.dart';

/// "What's new", built into the app. Shown once after an update, for every
/// version newer than the one the user had.
///
/// When you release: bump `version:` in pubspec.yaml (e.g. 1.3.0+4), add an
/// entry here with the SAME version name and build number, newest first,
/// and tag the GitHub release with the same version (e.g. v1.3.0).
/// "What's new" is shown once, when the installed version is higher than
/// the last one the user saw.
const changelog = <ChangelogEntry>[
  ChangelogEntry(
    version: '1.4.0',
    build: 6,
    date: '2026-11-25',
    notes: [
      'Loans: money you lent and got back in the same month no longer counts as spending. Paid back in a later month, it stays counted in the month you lent it.',
      'Loans has Unpaid and Paid tabs, and each loan shows how your budget counts it.',
      'Marking a loan paid: pick Cash or an e-wallet and the day it was paid, and see your new balance and budget before you confirm.',
      'Budget shows "Loans returned this month". Tap it to see how it works.',
      'Remaining and the budget bar now move smoothly to their new values.',
      'Activity shows when a loan was taken out of your budget, and which loan a repayment belongs to.',
      'New empty Loans screen with an "Add a loan" button.',
    ],
  ),
  ChangelogEntry(
    version: '1.3.0',
    build: 5,
    date: '2026-11-22',
    notes: [
      'Swipe left or right to move between tabs, or tap the bottom bar for a smooth slide.',
      'The Debts and Loans buttons on Home show how many are still open.',
      'Business Mode in Settings: turn it on to show Business on Home and as a tab; turn it off to hide it. Your business records are kept.',
      'Available balance now shows two boxes: Cash, and Cards & e-wallets, each with its own total.',
      'Allow buttons: when your phone hasn\'t allowed something Pitaka needs (like notifications for reminders), Home shows an Allow button. See them all in Settings > Phone permissions.',
      'Installing an update now has an Allow button if Android needs your OK first.',
      'Smoother and cooler: lighter screens, faster totals and lists, and less work while you scroll or swipe.',
      'What\'s new now shows only once per update.',
      'Updated Privacy Policy and Terms.',
    ],
  ),
  ChangelogEntry(
    version: '1.2.1',
    build: 4,
    date: '2026-11-21',
    notes: [
      'Updates now download and install inside the app. No browser needed.',
      'Loans: when a loan you gave is paid back, the money is now added to Cash or your e-wallet instead of taken out.',
      'Adding the same transaction more than once now counts every one in your budget, balance and Loans.',
      'Orders are Complete or Paid. Status comes first, and the payment is entered only when you choose Paid; unpaid amounts still show on each order.',
      'What\'s new shows this update and the one before it.',
    ],
  ),
  ChangelogEntry(
    version: '1.2.0',
    build: 3,
    date: '2026-11-21',
    notes: [
      'New glass look, with smooth animations when switching tabs.',
      'Tap a recent transaction to see its details; swipe right to edit or delete it.',
      'Clear history in Settings removes all transactions (balances stay as they are).',
      'Loans: choose Cash or E-wallet when you mark one paid. The payment counts in your budget.',
      'Import is now in Settings.',
      'Update check now reads the latest release on GitHub.',
      'Pay Later was removed. Unpaid Pay Later items were moved to Debts.',
    ],
  ),
  ChangelogEntry(
    version: '1.1.0',
    build: 2,
    date: '2026-11-21',
    notes: [
      'Loans: mark "Loan" transactions as paid.',
      'Transfers can include an optional fee, shown before you confirm.',
      'Business side: capital, inventory with recipes and stock history, products, orders with a change calculator, and sales charts.',
      'Photos are encrypted, and backups now include them.',
      'Insights stops at the first month that has data.',
      'The app can tell you when a newer version is available.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.0',
    build: 1,
    date: '2026-11-01',
    notes: ['First release.'],
  ),
];