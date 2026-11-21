import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'domain/security/vault.dart';
import 'domain/services/app_lock_service.dart';
import 'domain/services/notification_service.dart';
import 'presentation/providers/app_state_providers.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/screens/auth/forgot_password_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/recovery_key_screen.dart';
import 'presentation/screens/auth/sign_up_screen.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const _Bootstrap());
}

enum _Stage { loading, signUp, recoveryKey, login, forgot, unlocked, error }

/// Owns the login state. The encrypted database is only open while the
/// user is signed in; locking closes it and drops the key from memory.
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
  final _biometrics = AppLockService();
  bool _hasLegacyData = false;
  bool _biometricReady = false;

  // Set while unlocked (or while showing a new recovery key).
  AppDatabase? _db;
  Uint8List? _dataKey;
  Map<String, String> _settings = const {};
  String? _newRecoveryKey;

  /// Changes on every unlock so no provider state survives a lock.
  int _sessionId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _stage = _Stage.loading);
    try {
      _vault = Vault(await AppDatabase.directory());
      await _notifications.init();
      if (await _vault.exists()) {
        await _goToLogin();
      } else {
        _hasLegacyData = await AppDatabase.legacyExists();
        setState(() => _stage = _Stage.signUp);
      }
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

  Future<void> _goToLogin() async {
    final ready = await _biometrics.isBiometricEnabled() && await _biometrics.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricReady = ready;
      _stage = _Stage.login;
    });
  }

  // ---------------------------------------------------------------------------
  // Sign-up, login, recovery
  // ---------------------------------------------------------------------------

  Future<void> _createAccount(String password) async {
    final draft = await _vault.prepare(password);
    final passphrase = Vault.passphraseFor(draft.dataKey);
    final hadLegacy = await AppDatabase.legacyExists();
    if (hadLegacy) {
      await AppDatabase.encryptLegacy(passphrase: passphrase);
    } else {
      await AppDatabase.deleteOrphanedEncrypted();
    }
    // Opening proves the key works (and creates/migrates the schema)
    // before the vault is saved, so a failure leaves the old data intact.
    final db = await AppDatabase.open(passphrase: passphrase);
    await _vault.save(draft);
    if (hadLegacy) await AppDatabase.deleteLegacy();
    _db = db;
    _dataKey = draft.dataKey;
    setState(() {
      _newRecoveryKey = draft.recoveryKey;
      _stage = _Stage.recoveryKey;
    });
  }

  Future<void> _loginWithPassword(String password) async {
    final key = await _vault.unlockWithPassword(password);
    await _openWithKey(key);
  }

  Future<bool> _loginWithBiometric() async {
    final key = await _biometrics.unlockWithBiometrics();
    if (key == null) return false;
    await _openWithKey(key);
    return true;
  }

  Future<void> _resetPassword(String recoveryKey, String newPassword) async {
    final key = await _vault.resetPassword(recoveryKey: recoveryKey, newPassword: newPassword);
    await _openWithKey(key);
  }

  Future<void> _openWithKey(Uint8List key) async {
    final db = await AppDatabase.open(passphrase: Vault.passphraseFor(key));
    // Finish a migration that was interrupted after the vault was saved.
    if (await AppDatabase.legacyExists()) await AppDatabase.deleteLegacy();
    _db = db;
    _dataKey = key;
    await _enterApp();
  }

  Future<void> _enterApp() async {
    final db = _db!;
    final repo = SettingsRepository(db.db);
    // The old PIN lock is replaced by the password; drop its leftovers.
    for (final k in SettingsRepository.privateKeys) {
      await repo.remove(k);
    }
    _settings = await repo.all();
    if (!mounted) return;
    setState(() {
      _newRecoveryKey = null;
      _sessionId++;
      _stage = _Stage.unlocked;
    });
  }

  Future<void> _lock() async {
    final db = _db;
    // Tear down the app (and every provider holding data) right away.
    setState(() => _stage = _Stage.loading);
    _db = null;
    _dataKey = null;
    _settings = const {};
    await _goToLogin();
    // Close after the app's widgets (and their providers) are gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => db?.close());
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.unlocked) {
      return ProviderScope(
        key: ValueKey(_sessionId),
        overrides: [
          databaseProvider.overrideWithValue(_db!),
          initialSettingsProvider.overrideWithValue(_settings),
          notificationServiceProvider.overrideWithValue(_notifications),
          sessionProvider.overrideWithValue(Session(vault: _vault, dataKey: _dataKey!, lock: _lock)),
        ],
        child: const PitakaApp(),
      );
    }

    final Widget home = switch (_stage) {
      _Stage.signUp => SignUpScreen(hasExistingData: _hasLegacyData, onCreate: _createAccount),
      _Stage.recoveryKey => RecoveryKeyScreen(recoveryKey: _newRecoveryKey!, onDone: _enterApp),
      _Stage.login => LoginScreen(
          key: ValueKey('login-$_sessionId'),
          onPassword: _loginWithPassword,
          onBiometric: _biometricReady ? _loginWithBiometric : null,
          onForgot: () => setState(() => _stage = _Stage.forgot),
        ),
      _Stage.forgot => ForgotPasswordScreen(
          onReset: _resetPassword,
          onBack: () => setState(() => _stage = _Stage.login),
        ),
      _Stage.error => _StartupError(error: _error, onRetry: _init),
      _Stage.loading || _Stage.unlocked => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };

    // Theme settings live in the encrypted database, so the login screens
    // use the default accent and follow the system light/dark mode.
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
