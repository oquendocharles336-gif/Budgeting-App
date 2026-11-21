import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/debt_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/sms_pattern_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/sources/sms_inbox.dart';
import '../../domain/import/transaction_import_service.dart';
import '../../domain/services/app_lock_service.dart';
import '../../domain/services/backup_service.dart';
import '../../domain/services/budget_alert_service.dart';
import '../../domain/services/debt_service.dart';
import '../../domain/services/notification_service.dart';
import '../../domain/services/transaction_service.dart';

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

final smsInboxProvider = Provider<SmsInbox>((ref) => AndroidSmsInbox());

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
  ),
);

final transactionServiceProvider = Provider(
  (ref) => TransactionService(
    repository: ref.watch(transactionRepositoryProvider),
    importer: ref.watch(importServiceProvider),
    alerts: ref.watch(budgetAlertServiceProvider),
  ),
);

final debtServiceProvider = Provider(
  (ref) => DebtService(
    repository: ref.watch(debtRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
  ),
);

final backupServiceProvider = Provider((ref) => BackupService(ref.watch(databaseProvider).db));

final appLockServiceProvider = Provider((ref) => AppLockService(ref.watch(settingsRepositoryProvider)));

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
