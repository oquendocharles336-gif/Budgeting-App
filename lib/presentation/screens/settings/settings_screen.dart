import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/legal_text.dart';
import '../../../core/money.dart';
import '../../../data/db/seed_data.dart';
import '../../../domain/security/password_crypto.dart';
import '../../../domain/services/app_lock_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/animated_icons.dart';
import '../../widgets/password_dialog.dart';
import '../../widgets/photo_migration_line.dart';
import '../auth/recovery_key_screen.dart';
import '../auth/sign_up_screen.dart';
import '../cards/cards_screen.dart';
import '../business/business_shell.dart';
import '../debts/debts_screen.dart';
import '../legal/legal_document_screen.dart';
import '../loans/loans_screen.dart';
import '../pay_later/pay_later_screen.dart';
import 'categories_screen.dart';
import 'backup_screen.dart';
import 'change_password_screen.dart';
import 'rules_screen.dart';
import 'sms_patterns_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _biometricAvailable = false;
  bool _biometricOn = false;
  UnlockMethod _method = UnlockMethod.pin;

  /// "Lock now" closes the padlock first, then locks.
  bool _locking = false;

  Future<void> _lockNow() async {
    setState(() => _locking = true);
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (mounted) await ref.read(sessionProvider).lock();
  }

  @override
  void initState() {
    super.initState();
    _loadSecurity();
  }

  Future<void> _loadSecurity() async {
    final lock = ref.read(appLockServiceProvider);
    final vault = ref.read(sessionProvider).vault;
    final available = await lock.canUseBiometrics();
    final on = await lock.isBiometricEnabled();
    final hasPassword = await vault.hasPassword();
    final saved = await lock.savedMethod();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricOn = on;
        // Same rule as at start-up: no in-app password means phone lock.
        _method = !hasPassword ? UnlockMethod.device : (saved ?? UnlockMethod.pin);
      });
    }
  }

  bool get _usesDeviceLock => _method == UnlockMethod.device;

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeControllerProvider);
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionHeader('Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
                      ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
                    ],
                    selected: {theme.mode},
                    onSelectionChanged: (s) => ref.read(themeControllerProvider.notifier).setMode(s.first),
                  ),
                  const SizedBox(height: 16),
                  Text('Theme colors', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  ColorPickerField(
                    colors: AppTheme.accentPalette,
                    selected: theme.accent,
                    onChanged: (c) => ref.read(themeControllerProvider.notifier).setAccent(c),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader('Money'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.currency_exchange_rounded),
                  title: const Text('Currency'),
                  subtitle: Text('${currency.name} (${currency.symbol})'),
                  onTap: _pickCurrency,
                ),
                ListTile(
                  leading: const Icon(Icons.category_rounded),
                  title: const Text('Categories'),
                  onTap: () => _push(const CategoriesScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_fix_high_rounded),
                  title: const Text('Auto-categorize rules'),
                  subtitle: const Text('Keywords that pick a category'),
                  onTap: () => _push(const RulesScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_rounded),
                  title: const Text('Cards & e-wallets'),
                  subtitle: const Text('Accounts and their balances'),
                  onTap: () => _push(const CardsScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.handshake_rounded),
                  title: const Text('Debts'),
                  onTap: () => _push(const DebtsScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Pay Later'),
                  subtitle: const Text('Bought now, paid later'),
                  onTap: () => _push(const PayLaterScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.request_quote_rounded),
                  title: const Text('Loans'),
                  subtitle: const Text('Transactions in the "Loan" category'),
                  onTap: () => _push(const LoansScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.storefront_rounded),
                  title: const Text('Business'),
                  subtitle: const Text('Capital, inventory, products, orders and sales'),
                  onTap: () => _push(const BusinessShell()),
                ),
                if (Platform.isAndroid)
                  ListTile(
                    leading: const Icon(Icons.sms_rounded),
                    title: const Text('SMS patterns'),
                    subtitle: const Text('How bank texts are read'),
                    onTap: () => _push(const SmsPatternsScreen()),
                  ),
              ],
            ),
          ),
          const SectionHeader('Security'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.enhanced_encryption_rounded),
                  title: Text('Your data is encrypted'),
                  subtitle: Text('Only your unlock method or recovery key can open it. Nobody else can, not even the developer.'),
                ),
                ListTile(
                  leading: Icon(_usesDeviceLock ? Icons.phonelink_lock_rounded : Icons.dialpad_rounded),
                  title: const Text('Unlock method'),
                  subtitle: Text(
                    _usesDeviceLock ? 'Phone screen lock (PIN, pattern, fingerprint or face)' : 'In-app PIN or password',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _changeMethod,
                ),
                if (!_usesDeviceLock)
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Change PIN or password'),
                    onTap: () => _push(const ChangePasswordScreen()),
                  ),
                ListTile(
                  leading: const Icon(Icons.key_rounded),
                  title: const Text('New recovery key'),
                  subtitle: const Text('Lost your recovery key? Make a new one; the old one stops working'),
                  onTap: _newRecoveryKey,
                ),
                if (_biometricAvailable && !_usesDeviceLock)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Unlock with fingerprint / face'),
                    subtitle: const Text('Your key is kept in the phone\'s secure keystore. Your PIN always works too.'),
                    value: _biometricOn,
                    onChanged: (on) async {
                      final svc = ref.read(appLockServiceProvider);
                      if (on) {
                        final dataKey = ref.read(sessionProvider).dataKey;
                        if (!await LockGuard.run(() => svc.enableBiometric(dataKey))) return;
                      } else {
                        await svc.disableBiometric();
                      }
                      if (mounted) setState(() => _biometricOn = on);
                    },
                  ),
                ListTile(
                  leading: AnimatedLockIcon(unlocked: !_locking),
                  title: const Text('Lock now'),
                  subtitle: const Text('Also happens whenever you leave the app'),
                  onTap: _locking ? null : _lockNow,
                ),
              ],
            ),
          ),
          const SectionHeader('Your data'),
          const PhotoMigrationLine(),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.table_view_rounded),
                  title: const Text('Export transactions (CSV)'),
                  subtitle: const Text('Opens in Excel or Google Sheets'),
                  onTap: _exportCsv,
                ),
                ListTile(
                  leading: const Icon(Icons.backup_rounded),
                  title: const Text('Backup & restore'),
                  subtitle: const Text('All data and photos in one password-encrypted file'),
                  onTap: () => _push(const BackupScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.science_rounded),
                  title: const Text('Load sample data'),
                  subtitle: const Text('Adds demo cards, transactions, budgets and debts'),
                  onTap: _loadSample,
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                  title: Text('Delete all my data', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  subtitle: const Text('Personal and business data, and saved photos'),
                  onTap: _deleteAll,
                ),
              ],
            ),
          ),
          const SectionHeader('Legal'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  onTap: () => _push(const LegalDocumentScreen(title: 'Privacy Policy', body: LegalText.privacyPolicy)),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms & Conditions'),
                  onTap: () => _push(const LegalDocumentScreen(title: 'Terms & Conditions', body: LegalText.terms)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Pitaka 1.0 · All data stays on this device',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCurrency() async {
    final current = ref.read(currencyProvider);
    final picked = await showModalBottomSheet<CurrencyInfo>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in CurrencyInfo.all)
              ListTile(
                leading: SizedBox(width: 36, child: Center(child: Text(c.symbol, style: const TextStyle(fontSize: 18)))),
                title: Text(c.name),
                subtitle: Text(c.code),
                selected: c.code == current.code,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await ref.read(currencyProvider.notifier).set(picked);
  }

  String get _stamp => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  Future<void> _save(String fileName, String content, String mime) async {
    try {
      final uri = await LockGuard.run(() => FilePicker.saveFile(
            dialogTitle: 'Save file',
            fileName: fileName,
            bytes: Uint8List.fromList(utf8.encode(content)),
            mimeType: mime,
          ));
      if (!mounted) return;
      if (uri != null) showSnack(context, 'Saved $fileName');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e', error: true);
    }
  }

  Future<void> _exportCsv() async {
    final ok = await confirm(
      context,
      title: 'Export unencrypted CSV?',
      message: 'CSV files can\'t be encrypted. Anyone who gets the file can read your transactions. '
          'For a safe copy, use "Back up everything" instead.',
      confirmLabel: 'Export anyway',
      destructive: false,
    );
    if (!ok) return;
    final csv = await ref.read(backupServiceProvider).exportTransactionsCsv();
    await _save('pitaka_transactions_$_stamp.csv', csv, 'text/csv');
  }

  /// Device-lock method: the phone confirms it's the owner.
  Future<bool> _confirmWithDevice(String reason) async {
    final outcome = await LockGuard.run(() => ref.read(appLockServiceProvider).authenticateDevice(reason: reason));
    if (!outcome.ok && mounted) showSnack(context, outcome.message, error: true);
    return outcome.ok;
  }

  Future<void> _changeMethod() async {
    final svc = ref.read(appLockServiceProvider);
    final deviceSupported = await svc.isDeviceSupported();
    if (!mounted) return;
    final picked = await showModalBottomSheet<UnlockMethod>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phonelink_lock_rounded),
              title: const Text('Phone screen lock'),
              subtitle: Text(
                deviceSupported
                    ? 'Your phone PIN, pattern or password, plus fingerprint or face'
                    : 'Turn on a screen lock in your phone settings first',
              ),
              enabled: deviceSupported,
              selected: _usesDeviceLock,
              trailing: _usesDeviceLock ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, UnlockMethod.device),
            ),
            ListTile(
              leading: const Icon(Icons.dialpad_rounded),
              title: const Text('In-app PIN or password'),
              subtitle: const Text('A separate code just for Pitaka'),
              selected: !_usesDeviceLock,
              trailing: !_usesDeviceLock ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, UnlockMethod.pin),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _method || !mounted) return;
    final session = ref.read(sessionProvider);
    try {
      if (picked == UnlockMethod.device) {
        if (!await _confirmWithDevice('Confirm to unlock Pitaka with your phone lock')) return;
        // Order matters if the app is killed midway: the phone copy of the
        // key and the method are saved before the PIN stops working.
        await svc.storeDeviceKey(session.dataKey);
        await svc.saveMethod(UnlockMethod.device);
        await session.vault.removePassword();
        await svc.disableBiometric();
        await svc.clearAttempts();
        if (mounted) showSnack(context, 'Pitaka now unlocks with your phone lock');
      } else {
        if (deviceSupported && !await _confirmWithDevice('Confirm to set an in-app PIN')) return;
        if (!mounted) return;
        final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => SignUpScreen(
            hasExistingData: false,
            title: 'Set an in-app PIN',
            message: 'This PIN or password will unlock Pitaka instead of your phone lock.',
            buttonLabel: 'Save',
            showRecoveryNote: false,
            backLabel: 'Cancel',
            onBack: () => Navigator.pop(ctx, false),
            onCreate: (pw) async {
              await session.vault.setPassword(session.dataKey, pw);
              await svc.saveMethod(UnlockMethod.pin);
              await svc.deleteDeviceKey();
              await svc.clearAttempts();
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
          ),
        ));
        if ((done ?? false) && mounted) showSnack(context, 'Pitaka now unlocks with your in-app PIN');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not change the unlock method: $e', error: true);
    }
    await _loadSecurity();
  }

  Future<void> _newRecoveryKey() async {
    final vault = ref.read(sessionProvider).vault;
    String? newKey;
    if (_usesDeviceLock) {
      if (!await _confirmWithDevice('Confirm to make a new recovery key')) return;
      try {
        newKey = await vault.replaceRecoveryKeyWith(ref.read(sessionProvider).dataKey);
      } catch (e) {
        if (mounted) showSnack(context, 'Could not make a new recovery key: $e', error: true);
        return;
      }
    } else {
      await askPassword(
        context,
        title: 'New recovery key',
        message: 'Enter your PIN or password. Your old recovery key will stop working.',
        label: 'PIN or password',
        confirmLabel: 'Create',
        check: (pw) async {
          try {
            newKey = await vault.replaceRecoveryKey(password: pw);
            return null;
          } on WrongSecretException {
            return 'Wrong PIN or password';
          }
        },
      );
    }
    final key = newKey;
    if (key == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => RecoveryKeyScreen(recoveryKey: key, onDone: () => Navigator.of(ctx).pop()),
    ));
  }

  Future<void> _loadSample() async {
    final ok = await confirm(
      context,
      title: 'Load sample data?',
      message: 'Adds 3 cards, about 2 months of transactions, budgets and 2 debts. You can delete it all later.',
      confirmLabel: 'Load',
      destructive: false,
    );
    if (!ok) return;
    try {
      await SeedData.load(ref.read(databaseProvider).db);
      ref.refreshData();
      if (mounted) showSnack(context, 'Sample data added');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load sample data: $e', error: true);
    }
  }

  Future<void> _deleteAll() async {
    final ok = await confirm(
      context,
      title: 'Delete all my data?',
      message: 'This permanently removes every card, transaction, budget, debt, Pay Later item and custom category, '
          'plus all business data (capital, stock history, inventory, recipes, products, orders), '
          'the photos you added and their encryption key. '
          'Your password, theme and currency are kept. It cannot be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!ok) return;
    try {
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(backupServiceProvider).deleteAllData();
      await ref.read(photoServiceProvider).deleteAll();
    } catch (e) {
      ref.refreshData();
      if (mounted) showSnack(context, 'Could not delete everything: $e', error: true);
      return;
    }
    ref.refreshData();
    if (mounted) showSnack(context, 'All data deleted');
  }
}
