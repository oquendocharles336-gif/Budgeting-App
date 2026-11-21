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
import '../../../domain/services/backup_crypto.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/password_dialog.dart';
import '../auth/recovery_key_screen.dart';
import '../cards/cards_screen.dart';
import '../debts/debts_screen.dart';
import '../legal/legal_document_screen.dart';
import 'categories_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadBiometric();
  }

  Future<void> _loadBiometric() async {
    final lock = ref.read(appLockServiceProvider);
    final available = await lock.canUseBiometrics();
    final on = await lock.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricOn = on;
      });
    }
  }

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
                  Text('Accent color', style: Theme.of(context).textTheme.titleSmall),
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
                  leading: const Icon(Icons.credit_card_rounded),
                  title: const Text('Cards'),
                  onTap: () => _push(const CardsScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.handshake_rounded),
                  title: const Text('Debts'),
                  onTap: () => _push(const DebtsScreen()),
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
                  subtitle: Text('Only your password or recovery key can unlock it. Nobody else can, not even the developer.'),
                ),
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Change password'),
                  onTap: () => _push(const ChangePasswordScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.key_rounded),
                  title: const Text('New recovery key'),
                  subtitle: const Text('Lost your recovery key? Make a new one; the old one stops working'),
                  onTap: _newRecoveryKey,
                ),
                if (_biometricAvailable)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Unlock with fingerprint / face'),
                    subtitle: const Text('Your key is kept in the phone\'s secure keystore. The password always works too.'),
                    value: _biometricOn,
                    onChanged: (on) async {
                      final svc = ref.read(appLockServiceProvider);
                      if (on) {
                        if (!await svc.enableBiometric(ref.read(sessionProvider).dataKey)) return;
                      } else {
                        await svc.disableBiometric();
                      }
                      if (mounted) setState(() => _biometricOn = on);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.lock_rounded),
                  title: const Text('Lock now'),
                  subtitle: const Text('Also happens after 30 seconds in the background'),
                  onTap: () => ref.read(sessionProvider).lock(),
                ),
              ],
            ),
          ),
          const SectionHeader('Your data'),
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
                  title: const Text('Back up everything (encrypted)'),
                  subtitle: const Text('A backup file that only opens with your password'),
                  onTap: _exportJson,
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore_rounded),
                  title: const Text('Restore from backup'),
                  subtitle: const Text('Replaces all current data'),
                  onTap: _restore,
                ),
                ListTile(
                  leading: const Icon(Icons.science_rounded),
                  title: const Text('Load sample data'),
                  subtitle: const Text('Adds demo cards, transactions, budgets and debts'),
                  onTap: _loadSample,
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                  title: Text('Delete all data', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save file',
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: mime,
      );
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

  Future<void> _exportJson() async {
    final vault = ref.read(sessionProvider).vault;
    final password = await askPassword(
      context,
      title: 'Encrypt backup',
      message: 'Enter your password. The backup can only be opened with this password.',
      confirmLabel: 'Back up',
      check: (pw) async => await vault.verifyPassword(pw) ? null : 'Wrong password',
    );
    if (password == null || !mounted) return;
    try {
      final json = await ref.read(backupServiceProvider).exportJson();
      final encrypted = await BackupCrypto.encrypt(json, password);
      await _save('pitaka_backup_$_stamp.json', encrypted, 'application/json');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not create backup: $e', error: true);
    }
  }

  Future<void> _newRecoveryKey() async {
    final vault = ref.read(sessionProvider).vault;
    String? newKey;
    await askPassword(
      context,
      title: 'New recovery key',
      message: 'Enter your password. Your old recovery key will stop working.',
      confirmLabel: 'Create',
      check: (pw) async {
        try {
          newKey = await vault.replaceRecoveryKey(password: pw);
          return null;
        } on WrongSecretException {
          return 'Wrong password';
        }
      },
    );
    final key = newKey;
    if (key == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => RecoveryKeyScreen(recoveryKey: key, onDone: () => Navigator.of(ctx).pop()),
    ));
  }

  Future<void> _restore() async {
    final ok = await confirm(
      context,
      title: 'Restore a backup?',
      message: 'Everything currently in the app will be replaced by the backup. Make a backup first if unsure.',
      confirmLabel: 'Choose file',
      destructive: false,
    );
    if (!ok) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json']);
      if (file == null) return;
      var text = utf8.decode(await file.readAsBytes());
      if (BackupCrypto.isEncrypted(text)) {
        final encrypted = text;
        String? plain;
        if (!mounted) return;
        await askPassword(
          context,
          title: 'Backup password',
          message: 'Enter the password this backup was made with.',
          confirmLabel: 'Restore',
          check: (pw) async {
            try {
              plain = await BackupCrypto.decrypt(encrypted, pw);
              return null;
            } on WrongSecretException catch (e) {
              return e.message;
            }
          },
        );
        if (plain == null) return;
        text = plain!;
      }
      await ref.read(backupServiceProvider).restoreJson(text);
      final restored = await ref.read(settingsRepositoryProvider).all();
      ref.read(themeControllerProvider.notifier).reloadFrom(restored);
      ref.read(currencyProvider.notifier).reloadFrom(restored);
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(debtServiceProvider).rescheduleAll(currencySymbol: ref.read(currencyProvider).symbol);
      ref.refreshData();
      if (mounted) showSnack(context, 'Backup restored');
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
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
      title: 'Delete all data?',
      message: 'This permanently removes every card, transaction, budget, debt and custom category on this phone. '
          'Your password, theme and currency are kept. It cannot be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!ok) return;
    await ref.read(notificationServiceProvider).cancelAll();
    await ref.read(backupServiceProvider).deleteAllData();
    ref.refreshData();
    if (mounted) showSnack(context, 'All data deleted');
  }
}
