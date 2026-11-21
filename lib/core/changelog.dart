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