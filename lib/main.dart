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
import 'presentation/screens/auth/auth_widgets.dart';
import 'presentation/screens/auth/device_lock_screen.dart';
import 'presentation/screens/auth/forgot_password_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/recovery_key_screen.dart';
import 'presentation/screens/auth/security_setup_screen.dart';
import 'presentation/screens/auth/sign_up_screen.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled typeface's license, listed with the packages' licenses in
  // Settings > Legal > Open-source licenses.
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Plus Jakarta Sans'], ofl);
  });

  runApp(const _Bootstrap());
}

enum _Stage { loading, chooseMethod, signUp, recoveryKey, login, deviceLock, setPinFallback, forgot, unlocked, error }

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
  final _lockService = AppLockService();
  bool _hasLegacyData = false;
  bool _biometricReady = false;
  bool _deviceSupported = false;

  /// Shown by the forgot screen when it was opened because the phone lock
  /// can't be used any more.
  String? _forgotReason;

  // Set while unlocked (or while showing a new recovery key).
  AppDatabase? _db;
  Uint8List? _dataKey;
  Map<String, String> _settings = const {};
  String? _newRecoveryKey;

  /// Phone lock was removed: the key read from the keystore, waiting for
  /// the user to set an in-app PIN.
  Uint8List? _pendingKey;

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
        _deviceSupported = await _lockService.isDeviceSupported();
        if (mounted) setState(() => _stage = _Stage.chooseMethod);
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

  /// The saved method, checked against the vault: without an in-app
  /// password only the phone lock can work. Vaults from before the choice
  /// existed always have a password.
  Future<UnlockMethod> _currentMethod() async {
    final saved = await _lockService.savedMethod();
    final hasPassword = await _vault.hasPassword();
    if (!hasPassword) return UnlockMethod.device;
    return saved ?? UnlockMethod.pin;
  }

  Future<void> _goToLogin() async {
    try {
      final method = await _currentMethod();
      if (method == UnlockMethod.device) {
        if (!await _lockService.isDeviceSupported()) {
          await _onDeviceLockMissing();
          return;
        }
        if (mounted) setState(() => _stage = _Stage.deviceLock);
        return;
      }
      final ready = await _lockService.isBiometricEnabled() && await _lockService.canUseBiometrics();
      if (!mounted) return;
      setState(() {
        _biometricReady = ready;
        _stage = _Stage.login;
      });
    } catch (e) {
      _fail(e);
    }
  }

  /// The user turned off their phone's screen lock. The key is still in the
  /// app's keystore entry, so ask for an in-app PIN to protect it from now
  /// on. If the keystore lost it too, only the recovery key can help.
  Future<void> _onDeviceLockMissing() async {
    final key = await _lockService.readDeviceKey();
    if (!mounted) return;
    setState(() {
      if (key != null) {
        _pendingKey = key;
        _stage = _Stage.setPinFallback;
      } else {
        _forgotReason = 'The phone lock can\'t be used any more. Enter your recovery key to set an in-app PIN.';
        _stage = _Stage.forgot;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // First set-up
  // ---------------------------------------------------------------------------

  /// Creates the encrypted database for [draft] and, once it opens, saves
  /// the vault. A failure leaves any old data intact.
  Future<void> _setUp(VaultDraft draft, {required Future<void> Function() beforeVaultSaved}) async {
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
    try {
      await beforeVaultSaved();
      await _vault.save(draft);
    } catch (e) {
      await db.close();
      rethrow;
    }
    if (hadLegacy) await AppDatabase.deleteLegacy();
    _db = db;
    _dataKey = draft.dataKey;
    setState(() {
      _newRecoveryKey = draft.recoveryKey;
      _stage = _Stage.recoveryKey;
    });
  }

  /// Option B: in-app PIN / password.
  Future<void> _createWithPin(String password) async {
    final draft = await _vault.prepare(password);
    await _setUp(draft, beforeVaultSaved: () async {
      await _lockService.deleteDeviceKey();
      await _lockService.clearAttempts();
      await _lockService.saveMethod(UnlockMethod.pin);
    });
  }

  /// Option A: the phone's screen lock. The phone confirms first, so a
  /// phone that can't actually show its lock never ends up as the method.
  Future<void> _createWithDevice() async {
    final outcome = await _lockService.authenticateDevice(reason: 'Confirm it\'s you to secure Pitaka');
    if (!outcome.ok) {
      if (outcome.deviceLockMissing && mounted) {
        setState(() => _deviceSupported = false);
      }
      throw _SetupMessage(outcome.message);
    }
    final draft = await _vault.prepareWithoutPassword();
    await _setUp(draft, beforeVaultSaved: () async {
      await _lockService.storeDeviceKey(draft.dataKey);
      await _lockService.disableBiometric();
      await _lockService.saveMethod(UnlockMethod.device);
    });
  }

  // ---------------------------------------------------------------------------
  // Unlocking
  // ---------------------------------------------------------------------------

  Future<void> _loginWithPassword(String password) async {
    final key = await _vault.unlockWithPassword(password);
    await _lockService.clearAttempts();
    await _openWithKey(key);
  }

  Future<bool> _loginWithBiometric() async {
    final key = await _lockService.unlockWithBiometrics();
    if (key == null) return false;
    await _openWithKey(key);
    return true;
  }

  Future<DeviceAuthOutcome> _loginWithDevice() async {
    final outcome = await _lockService.authenticateDevice();
    if (!outcome.ok) return outcome;
    final key = await _lockService.readDeviceKey();
    if (key == null) {
      return const DeviceAuthOutcome(
        DeviceAuthStatus.failed,
        'The unlock key is missing from this phone\'s keystore. Use your recovery key.',
      );
    }
    await _openWithKey(key);
    return outcome;
  }

  /// Phone lock removed: protect the key with a new in-app PIN.
  Future<void> _setFallbackPin(String password) async {
    final key = _pendingKey!;
    await _vault.setPassword(key, password);
    await _lockService.saveMethod(UnlockMethod.pin);
    await _lockService.deleteDeviceKey();
    await _lockService.clearAttempts();
    _pendingKey = null;
    await _openWithKey(key);
  }

  /// Recovery key: sets an in-app PIN, which becomes the unlock method.
  Future<void> _resetPassword(String recoveryKey, String newPassword) async {
    final key = await _vault.resetPassword(recoveryKey: recoveryKey, newPassword: newPassword);
    await _lockService.saveMethod(UnlockMethod.pin);
    await _lockService.deleteDeviceKey();
    await _lockService.clearAttempts();
    _forgotReason = null;
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
    // Only those: removing every private key here wiped "What's new" seen,
    // the last update check and the camera photo draft on every unlock.
    for (final k in SettingsRepository.legacyLockKeys) {
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
    if (_stage != _Stage.unlocked) return;
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
          appLockServiceProvider.overrideWithValue(_lockService),
          sessionProvider.overrideWithValue(Session(vault: _vault, dataKey: _dataKey!, lock: _lock)),
        ],
        child: const PitakaApp(),
      );
    }

    final Widget home = switch (_stage) {
      _Stage.chooseMethod => SecuritySetupScreen(
          deviceSupported: _deviceSupported,
          hasExistingData: _hasLegacyData,
          onUseDevice: _createWithDevice,
          onUsePin: () => setState(() => _stage = _Stage.signUp),
        ),
      _Stage.signUp => SignUpScreen(
          hasExistingData: _hasLegacyData,
          onCreate: _createWithPin,
          onBack: () => setState(() => _stage = _Stage.chooseMethod),
        ),
      _Stage.recoveryKey => RecoveryKeyScreen(recoveryKey: _newRecoveryKey!, onDone: _enterApp),
      _Stage.login => LoginScreen(
          key: ValueKey('login-$_sessionId'),
          onPassword: _loginWithPassword,
          onBiometric: _biometricReady ? _loginWithBiometric : null,
          onForgot: () => setState(() => _stage = _Stage.forgot),
          lockService: _lockService,
        ),
      _Stage.deviceLock => DeviceLockScreen(
          key: ValueKey('device-$_sessionId'),
          onUnlock: _loginWithDevice,
          onDeviceLockMissing: _onDeviceLockMissing,
          onRecovery: () => setState(() => _stage = _Stage.forgot),
        ),
      _Stage.setPinFallback => SignUpScreen(
          hasExistingData: false,
          title: 'Set an in-app PIN',
          message: 'Your phone no longer has a screen lock, so Pitaka can\'t use it. '
              'Set a PIN or password to keep your data protected.',
          buttonLabel: 'Set PIN and unlock',
          showRecoveryNote: false,
          onCreate: _setFallbackPin,
        ),
      _Stage.forgot => ForgotPasswordScreen(
          reason: _forgotReason,
          onReset: _resetPassword,
          onBack: () {
            _forgotReason = null;
            _goToLogin();
          },
        ),
      _Stage.error => _StartupError(error: _error, onRetry: _init),
      // Brief: opening the database. The logo instead of a spinner.
      _Stage.loading || _Stage.unlocked => const Scaffold(body: Center(child: AppLogo(size: 96))),
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

/// A set-up problem whose text is shown to the user as is.
class _SetupMessage implements Exception {
  const _SetupMessage(this.message);
  final String message;
  @override
  String toString() => message;
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
