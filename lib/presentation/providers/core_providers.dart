import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/business_repositories.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/debt_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/sms_pattern_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../core/app_update_config.dart';
import '../../data/sources/photo_store.dart';
import '../../data/sources/release_feed.dart';
import '../../data/sources/sms_inbox.dart';
import '../../data/sources/wallet_notifications.dart';
import '../../domain/import/transaction_import_service.dart';
import '../../domain/security/photo_crypto.dart';
import '../../domain/security/vault.dart';
import '../../domain/services/app_lock_service.dart';
import '../../domain/services/auto_track_service.dart';
import '../../domain/services/backup_bundle_service.dart';
import '../../domain/services/backup_service.dart';
import '../../domain/services/budget_alert_service.dart';
import '../../domain/services/business_service.dart';
import '../../domain/services/debt_service.dart';
import '../../domain/services/notification_service.dart';
import '../../domain/services/phone_access_service.dart';
import '../../domain/services/photo_service.dart';
import '../../domain/services/transaction_service.dart';
import '../../domain/services/update_service.dart';

// -----------------------------------------------------------------------------
// Overridden in main() once the database is open.
// -----------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden in main()'),
);

/// Settings read before the first frame (theme, currency, terms, lock).
final initialSettingsProvider = Provider<Map<String, String>>(
  (ref) => throw UnimplementedError('initialSettingsProvider must be overridden in main()'),
);

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

/// The signed-in session: the vault (password / recovery key), the data
/// key that is unlocking the database right now, and a way to lock again.
class Session {
  const Session({required this.vault, required this.dataKey, required this.lock});
  final Vault vault;

  /// Kept in memory only while unlocked (SQLCipher needs it anyway).
  final Uint8List dataKey;

  /// Closes the database, forgets the key and shows the login screen.
  final Future<void> Function() lock;
}

final sessionProvider = Provider<Session>(
  (ref) => throw UnimplementedError('sessionProvider must be overridden in main()'),
);

// -----------------------------------------------------------------------------
// Repositories (data layer)
// -----------------------------------------------------------------------------

final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.watch(databaseProvider).db));
final cardRepositoryProvider = Provider((ref) => CardRepository(ref.watch(databaseProvider).db));
final transactionRepositoryProvider = Provider((ref) => TransactionRepository(ref.watch(databaseProvider).db));
final categoryRepositoryProvider = Provider((ref) => CategoryRepository(ref.watch(databaseProvider).db));
final ruleRepositoryProvider = Provider((ref) => RuleRepository(ref.watch(databaseProvider).db));
final debtRepositoryProvider = Provider((ref) => DebtRepository(ref.watch(databaseProvider).db));
final budgetRepositoryProvider = Provider((ref) => BudgetRepository(ref.watch(databaseProvider).db));
final smsPatternRepositoryProvider = Provider((ref) => SmsPatternRepository(ref.watch(databaseProvider).db));
final capitalRepositoryProvider = Provider((ref) => CapitalRepository(ref.watch(databaseProvider).db));
final inventoryRepositoryProvider = Provider((ref) => InventoryRepository(ref.watch(databaseProvider).db));
final productRepositoryProvider = Provider((ref) => ProductRepository(ref.watch(databaseProvider).db));
final orderRepositoryProvider = Provider((ref) => OrderRepository(ref.watch(databaseProvider).db));

final smsInboxProvider = Provider<SmsInbox>((ref) => AndroidSmsInbox());
final walletNotificationsProvider = Provider<WalletNotificationSource>((ref) => const AndroidWalletNotifications());
final photoStoreProvider = Provider((ref) => PhotoStore());
final photoKeyStoreProvider = Provider<PhotoKeyStore>((ref) => SecurePhotoKeyStore());
final photoCryptoProvider = Provider((ref) => PhotoCrypto(ref.watch(photoKeyStoreProvider)));

// -----------------------------------------------------------------------------
// Services (domain layer)
// -----------------------------------------------------------------------------

final budgetAlertServiceProvider = Provider(
  (ref) => BudgetAlertService(
    budgets: ref.watch(budgetRepositoryProvider),
    transactions: ref.watch(transactionRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
  ),
);

final importServiceProvider = Provider(
  (ref) => TransactionImportService(
    transactions: ref.watch(transactionRepositoryProvider),
    rules: ref.watch(ruleRepositoryProvider),
    alerts: ref.watch(budgetAlertServiceProvider),
    categories: ref.watch(categoryRepositoryProvider),
  ),
);

final transactionServiceProvider = Provider(
  (ref) => TransactionService(
    repository: ref.watch(transactionRepositoryProvider),
    cards: ref.watch(cardRepositoryProvider),
    importer: ref.watch(importServiceProvider),
    alerts: ref.watch(budgetAlertServiceProvider),
    categories: ref.watch(categoryRepositoryProvider),
  ),
);

/// Free automatic tracking (e-wallet app notifications + bank SMS).
final autoTrackServiceProvider = Provider(
  (ref) => AutoTrackService(
    cards: ref.watch(cardRepositoryProvider),
    patterns: ref.watch(smsPatternRepositoryProvider),
    importer: ref.watch(importServiceProvider),
    notifications: ref.watch(walletNotificationsProvider),
    sms: ref.watch(smsInboxProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

final debtServiceProvider = Provider(
  (ref) => DebtService(
    repository: ref.watch(debtRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
  ),
);

final photoServiceProvider = Provider(
  (ref) => PhotoService(
    store: ref.watch(photoStoreProvider),
    crypto: ref.watch(photoCryptoProvider),
    keys: ref.watch(photoKeyStoreProvider),
    inventory: ref.watch(inventoryRepositoryProvider),
    products: ref.watch(productRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

final businessServiceProvider = Provider(
  (ref) => BusinessService(
    capital: ref.watch(capitalRepositoryProvider),
    inventory: ref.watch(inventoryRepositoryProvider),
    products: ref.watch(productRepositoryProvider),
    orders: ref.watch(orderRepositoryProvider),
    transactions: ref.watch(transactionServiceProvider),
    categories: ref.watch(categoryRepositoryProvider),
    photos: ref.watch(photoServiceProvider),
  ),
);

final backupServiceProvider = Provider((ref) => BackupService(ref.watch(databaseProvider).db));

final backupBundleServiceProvider = Provider(
  (ref) => BackupBundleService(backup: ref.watch(backupServiceProvider), photos: ref.watch(photoServiceProvider)),
);

final appLockServiceProvider = Provider((ref) => AppLockService());

final phoneAccessServiceProvider = Provider(
  (ref) => PhoneAccessService(
    notifications: ref.watch(notificationServiceProvider),
    sms: ref.watch(smsInboxProvider),
  ),
);

final updateServiceProvider = Provider(
  (ref) => UpdateService(
    settings: ref.watch(settingsRepositoryProvider),
    fetchRelease: GitHubReleaseFeed(
      AppUpdateConfig.latestReleaseUri,
      repository: AppUpdateConfig.githubRepository,
    ).fetch,
    installed: readInstalledVersion,
  ),
);

// -----------------------------------------------------------------------------
// Data revision: every query provider watches this. After any write, call
// `ref.read(dataRevisionProvider.notifier).bump()` and all screens refresh.
// -----------------------------------------------------------------------------

class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final dataRevisionProvider = NotifierProvider<DataRevision, int>(DataRevision.new);

extension RefreshData on WidgetRef {
  /// Call after writing to the database.
  void refreshData() => read(dataRevisionProvider.notifier).bump();
}
