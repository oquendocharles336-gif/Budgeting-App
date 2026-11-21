import '../domain/update/app_update.dart';

/// "What's new", built into the app. Shown once after an update, for every
/// version newer than the one the user had.
///
/// When you release: bump `version:` in pubspec.yaml (e.g. 1.2.0+3), add an
/// entry here with the SAME build number (the number after "+"), newest
/// first, and put the same notes in your hosted version.json.
const changelog = <ChangelogEntry>[
  ChangelogEntry(
    version: '1.1.0',
    build: 2,
    date: '2026-11-21',
    notes: [
      'Pay Later: record purchases you\'ll pay later, with reminders 2 days before they\'re due.',
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
