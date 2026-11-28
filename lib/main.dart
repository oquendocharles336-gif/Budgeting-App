import 'dart:typed_data';

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'domain/security/vault.dart';
import 'domain/services/app_lock_service.dart';
import 'domain/services/notification_service.dart';
import 'presentation/providers/app_state_providers.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Plus Jakarta Sans'], ofl);
  });

  runApp(const _Bootstrap());
}

enum _Stage { loading, unlocked, error }

/// Bypasses login/password and opens the unencrypted database directly.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  _Stage _stage = _Stage.loading;
  Object? _error;
  late Vault _vault;
  final _notifications = NotificationService();
  final _lockService = AppLockService();

  AppDatabase? _db;
  Uint8List? _dataKey;
  Map<String, String> _settings = const {};
  int _sessionId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _stage = _Stage.loading);
    try {
      final dir = await AppDatabase.directory();
      _vault = Vault(dir);
      await _notifications.init();

      final db = await AppDatabase.openPlain();
      _db = db;
      _dataKey = Uint8List(32);

      final repo = SettingsRepository(db.db);
      for (final k in SettingsRepository.legacyLockKeys) {
        await repo.remove(k);
      }
      _settings = await repo.all();
      if (!mounted) return;
      setState(() {
        _sessionId++;
        _stage = _Stage.unlocked;
      });
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    debugPrint('Startup failed: $e');
    if (mounted) {
      setState(() {
        _error = e;
        _stage = _Stage.error;
      });
    }
  }

  Future<void> _lock() async {
    // No-op since password/lock has been removed.
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.unlocked) {
      return ProviderScope(
        key: ValueKey(_sessionId),
        overrides: [
          databaseProvider.overrideWithValue(_db!),
          initialSettingsProvider.overrideWithValue(_settings),
          notificationServiceProvider.overrideWithValue(_notifications),
          appLockServiceProvider.overrideWithValue(_lockService),
          sessionProvider.overrideWithValue(Session(vault: _vault, dataKey: _dataKey!, lock: _lock)),
        ],
        child: const PitakaApp(),
      );
    }

    final Widget home = switch (_stage) {
      _Stage.error => _StartupError(error: _error, onRetry: _init),
      _Stage.loading || _Stage.unlocked => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };

    return MaterialApp(
      title: 'Pitaka',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(ThemeSettings.defaultAccent),
      darkTheme: AppTheme.dark(ThemeSettings.defaultAccent),
      home: home,
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_rounded, size: 48),
                const SizedBox(height: 12),
                const Text('Could not open your data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
}
