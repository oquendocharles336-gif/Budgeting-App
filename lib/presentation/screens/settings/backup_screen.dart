import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/security/password_crypto.dart';
import '../../../domain/services/app_lock_service.dart';
import '../../../domain/services/backup_bundle_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/password_dialog.dart';

/// Back up everything (database + photos) into one password-encrypted
/// file, and restore it (replace or merge).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  /// What's running, for the inline progress line (null = idle).
  String? _busy;

  static String? validateBackupPassword(String pw) {
    if (pw.length < 8) return 'Use at least 8 characters';
    if (RegExp(r'^\d+$').hasMatch(pw)) return 'Add letters too: a number-only password is easy to guess';
    return null;
  }

  Future<String?> _newPassword() async {
    final first = await askPassword(
      context,
      title: 'Backup password',
      message: 'Choose a password for this backup file (8+ characters, not only numbers). '
          'You\'ll need it to restore. Nobody can recover it for you.',
      confirmLabel: 'Next',
      check: (pw) async => validateBackupPassword(pw),
    );
    if (first == null || !mounted) return null;
    return askPassword(
      context,
      title: 'Confirm backup password',
      message: 'Type the backup password again.',
      confirmLabel: 'Back up',
      check: (pw) async => pw == first ? null : 'That doesn\'t match',
    );
  }

  Future<void> _backup() async {
    final password = await _newPassword();
    if (password == null || !mounted) return;
    setState(() => _busy = 'Making the backup…');
    try {
      final text = await ref.read(backupBundleServiceProvider).export(password);
      final name = 'pitaka_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
      final saved = await LockGuard.run(() => FilePicker.saveFile(
            dialogTitle: 'Save backup',
            fileName: name,
            bytes: Uint8List.fromList(utf8.encode(text)),
            mimeType: 'application/json',
          ));
      if (mounted && saved != null) showSnack(context, 'Backup saved: $name');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not create the backup: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore() async {
    final bundle = ref.read(backupBundleServiceProvider);
    final String text;
    try {
      final file = await LockGuard.run(() => FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json']));
      if (file == null) return;
      text = utf8.decode(await file.readAsBytes());
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the file: $e', error: true);
      return;
    }
    if (!mounted) return;

    // 1. Password and contents are checked before anything changes.
    BackupData? data;
    try {
      data = await bundle.open(text, null);
    } on WrongSecretException {
      if (!mounted) return;
      await askPassword(
        context,
        title: 'Backup password',
        message: 'Enter the password this backup was made with.',
        confirmLabel: 'Open',
        check: (pw) async {
          try {
            data = await bundle.open(text, pw);
            return null;
          } on WrongSecretException catch (e) {
            return e.message;
          } on BackupException catch (e) {
            return e.message;
          }
        },
      );
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
      return;
    }
    final opened = data;
    if (opened == null || !mounted) return;

    // 2. Replace or merge, with what's in the file.
    final s = BackupSummary(opened);
    final mode = await showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Semantics(
          container: true,
          child: Text(
            'It has ${s.transactions} transactions, ${s.orders} orders, ${s.products} products, '
            '${s.inventory} inventory items and ${s.photos} photos.\n\n'
            'Replace: everything here is replaced by the backup.\n'
            'Merge: the backup is added next to what\'s here (same-name categories are reused; '
            'your settings and Cash balance stay as they are).',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, RestoreMode.merge), child: const Text('Merge')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, RestoreMode.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    // 3. All or nothing (see BackupBundleService).
    setState(() => _busy = 'Restoring…');
    try {
      await bundle.restore(opened, mode: mode);
      final restored = await ref.read(settingsRepositoryProvider).all();
      ref.read(themeControllerProvider.notifier).reloadFrom(restored);
      ref.read(currencyProvider.notifier).reloadFrom(restored);
      final symbol = ref.read(currencyProvider).symbol;
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(debtServiceProvider).rescheduleAll(currencySymbol: symbol);
      await ref.read(payLaterServiceProvider).rescheduleAll(currencySymbol: symbol);
      ref.refreshData();
      if (mounted) showSnack(context, mode == RestoreMode.replace ? 'Backup restored' : 'Backup merged');
    } catch (e) {
      if (mounted) showSnack(context, 'Nothing was changed. $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (busy != null)
            Semantics(
              liveRegion: true,
              label: busy,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(busy), const SizedBox(height: 6), const LinearProgressIndicator()],
                ),
              ),
            ),
          Semantics(
            container: true,
            label: 'Backup. One encrypted file with all your data and photos.',
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ListTile(
                    leading: Icon(Icons.backup_rounded),
                    title: Text('Back up everything'),
                    subtitle: Text(
                      'Personal and business data (capital, stock history, orders, products, inventory) '
                      'and every photo, in one file encrypted with a password you choose.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      onPressed: busy == null ? _backup : null,
                      icon: const Icon(Icons.lock_rounded),
                      label: const Text('Create encrypted backup'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: 'Restore. Replace or merge from a backup file.',
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ListTile(
                    leading: Icon(Icons.settings_backup_restore_rounded),
                    title: Text('Restore from a backup'),
                    subtitle: Text(
                      'The password and the file are checked first. Then you choose Replace or Merge. '
                      'If anything goes wrong, nothing here changes.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: OutlinedButton.icon(
                      onPressed: busy == null ? _restore : null,
                      icon: const Icon(Icons.file_open_rounded),
                      label: const Text('Choose backup file'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'The file is saved only where you choose. Photos are stored inside it, protected by the backup password, '
            'so the backup can be restored on another phone.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
