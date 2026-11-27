import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// How the user unlocks the app, chosen on first launch (and changeable in
/// Settings).
enum UnlockMethod {
  /// The phone's own screen lock: PIN / pattern / password, plus
  /// fingerprint or face where the phone has them.
  device,

  /// A PIN or password typed into the app.
  pin;

  static UnlockMethod? fromName(String? v) => switch (v) {
        'device' => UnlockMethod.device,
        'pin' => UnlockMethod.pin,
        _ => null,
      };
}

enum DeviceAuthStatus { success, canceled, lockedOut, notSetUp, notEnrolled, unavailable, failed }

/// Result of asking the phone to confirm it's the owner, with a message
/// that can be shown as is.
class DeviceAuthOutcome {
  const DeviceAuthOutcome(this.status, [this.message = '']);
  final DeviceAuthStatus status;
  final String message;

  bool get ok => status == DeviceAuthStatus.success;

  /// The phone has no usable screen lock any more.
  bool get deviceLockMissing => status == DeviceAuthStatus.notSetUp;
}

/// Wrong-PIN counter that survives closing the app, so guessing can't be
/// sped up by restarting it.
class PinAttempts {
  const PinAttempts({required this.failures, this.waitUntil});
  final int failures;
  final DateTime? waitUntil;

  /// After 5 wrong tries: 30 s, then 1, 2, 4, 8, 16 min.
  static DateTime? waitAfter(int failures, DateTime now) =>
      failures < 5 ? null : now.add(Duration(seconds: 30 * (1 << math.min(failures - 5, 5))));
}

/// Talks to the phone's lock (`local_auth`) and keeps the database key in
/// the OS keystore (`flutter_secure_storage`: Android Keystore / iOS
/// Keychain) when the phone's lock is used.
///
/// The app never receives the phone PIN, pattern, fingerprint or face; the
/// OS checks them and only answers yes or no.
class AppLockService {
  AppLockService({LocalAuthentication? auth, FlutterSecureStorage? storage})
      : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  /// Optional fingerprint shortcut when the in-app PIN is the method.
  static const _biometricKeyName = 'pitaka_data_key_v1';

  /// Database key when the phone's screen lock is the method.
  static const _deviceKeyName = 'pitaka_device_key_v1';
  static const _methodKeyName = 'pitaka_unlock_method';
  static const _attemptsKeyName = 'pitaka_pin_attempts';

  // ---------------------------------------------------------------------------
  // Chosen method
  // ---------------------------------------------------------------------------

  Future<UnlockMethod?> savedMethod() async {
    try {
      return UnlockMethod.fromName(await _storage.read(key: _methodKeyName));
    } catch (e) {
      debugPrint('Could not read unlock method: $e');
      return null;
    }
  }

  Future<void> saveMethod(UnlockMethod method) => _storage.write(key: _methodKeyName, value: method.name);

  // ---------------------------------------------------------------------------
  // Phone screen lock
  // ---------------------------------------------------------------------------

  /// True when the phone has a screen lock (PIN / pattern / password) or
  /// biometrics the app can use. False after the user removes their lock.
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('Device support check failed: $e');
      return false;
    }
  }

  /// Shows the phone's own unlock prompt. Fingerprint / face are offered
  /// where enrolled, and the phone PIN / pattern / password always works
  /// (`biometricOnly: false`).
  Future<DeviceAuthOutcome> authenticateDevice({String reason = 'Unlock Pitaka'}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok
          ? const DeviceAuthOutcome(DeviceAuthStatus.success)
          : const DeviceAuthOutcome(DeviceAuthStatus.failed, 'Not unlocked. Try again.');
    } on LocalAuthException catch (e) {
      debugPrint('Device auth failed: ${e.code} ${e.description}');
      return _outcomeFor(e);
    } on PlatformException catch (e) {
      // Missing permission / activity set-up problems end up here.
      debugPrint('Device auth platform error: ${e.code} ${e.message}');
      return DeviceAuthOutcome(
        DeviceAuthStatus.unavailable,
        'The phone\'s lock screen could not be shown (${e.code}). Try again, or use your recovery key.',
      );
    } catch (e) {
      debugPrint('Device auth failed: $e');
      return const DeviceAuthOutcome(DeviceAuthStatus.failed, 'Something went wrong. Try again.');
    }
  }

  static DeviceAuthOutcome _outcomeFor(LocalAuthException e) => switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback =>
          const DeviceAuthOutcome(DeviceAuthStatus.canceled, 'Unlock was canceled. Tap Unlock to try again.'),
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => const DeviceAuthOutcome(
            DeviceAuthStatus.lockedOut,
            'Too many attempts. Wait a little, then try again with your phone PIN, pattern or password.',
          ),
        LocalAuthExceptionCode.noCredentialsSet => const DeviceAuthOutcome(
            DeviceAuthStatus.notSetUp,
            'This phone has no screen lock. Set an in-app PIN instead.',
          ),
        LocalAuthExceptionCode.noBiometricsEnrolled => const DeviceAuthOutcome(
            DeviceAuthStatus.notEnrolled,
            'No fingerprint or face is set up. Use your phone PIN, pattern or password.',
          ),
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable =>
          const DeviceAuthOutcome(
            DeviceAuthStatus.unavailable,
            'The phone\'s unlock screen isn\'t available right now. Try again in a moment.',
          ),
        _ => DeviceAuthOutcome(
            DeviceAuthStatus.failed,
            'Could not unlock${e.description == null ? '' : ': ${e.description}'}. Try again.',
          ),
      };

  Future<void> storeDeviceKey(Uint8List dataKey) => _storage.write(key: _deviceKeyName, value: _hex(dataKey));

  /// The key kept for phone-lock unlocking. Only call after
  /// [authenticateDevice] succeeded, or when the phone lock was removed
  /// and the user is moving to an in-app PIN.
  Future<Uint8List?> readDeviceKey() async {
    try {
      return _unhex(await _storage.read(key: _deviceKeyName));
    } catch (e) {
      debugPrint('Could not read device key: $e');
      return null;
    }
  }

  Future<void> deleteDeviceKey() async {
    try {
      await _storage.delete(key: _deviceKeyName);
    } catch (e) {
      debugPrint('Could not remove device key: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Wrong PIN counter
  // ---------------------------------------------------------------------------

  Future<PinAttempts> loadAttempts() async {
    try {
      final v = await _storage.read(key: _attemptsKeyName);
      final parts = v?.split(':');
      if (parts == null || parts.length != 2) return const PinAttempts(failures: 0);
      final failures = int.tryParse(parts[0]) ?? 0;
      final until = int.tryParse(parts[1]) ?? 0;
      return PinAttempts(
        failures: failures,
        waitUntil: until == 0 ? null : DateTime.fromMillisecondsSinceEpoch(until),
      );
    } catch (_) {
      return const PinAttempts(failures: 0);
    }
  }

  Future<PinAttempts> recordFailure() async {
    final current = await loadAttempts();
    final failures = current.failures + 1;
    final until = PinAttempts.waitAfter(failures, DateTime.now());
    try {
      await _storage.write(key: _attemptsKeyName, value: '$failures:${until?.millisecondsSinceEpoch ?? 0}');
    } catch (e) {
      debugPrint('Could not save attempt count: $e');
    }
    return PinAttempts(failures: failures, waitUntil: until);
  }

  Future<void> clearAttempts() async {
    try {
      await _storage.delete(key: _attemptsKeyName);
    } catch (e) {
      debugPrint('Could not clear attempt count: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Optional fingerprint shortcut (in-app PIN method only)
  // ---------------------------------------------------------------------------

  Future<bool> canUseBiometrics() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (e) {
      debugPrint('Biometric check failed: $e');
      return false;
    }
  }

  Future<bool> isBiometricEnabled() async {
    try {
      return await _storage.containsKey(key: _biometricKeyName);
    } catch (e) {
      debugPrint('Secure storage unavailable: $e');
      return false;
    }
  }

  /// Asks for the fingerprint/face, then stores [dataKey]. Returns false if cancelled.
  Future<bool> enableBiometric(Uint8List dataKey) async {
    if (!await authenticateWithBiometrics()) return false;
    await _storage.write(key: _biometricKeyName, value: _hex(dataKey));
    return true;
  }

  Future<void> disableBiometric() async {
    try {
      await _storage.delete(key: _biometricKeyName);
    } catch (e) {
      debugPrint('Could not remove stored key: $e');
    }
  }

  /// Asks for the fingerprint/face and returns the stored data key, or null.
  Future<Uint8List?> unlockWithBiometrics() async {
    if (!await isBiometricEnabled()) return null;
    if (!await authenticateWithBiometrics()) return null;
    return _unhex(await _storage.read(key: _biometricKeyName));
  }

  /// Shows the system fingerprint/face prompt. Returns false on cancel or error.
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Pitaka',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      debugPrint('Biometric auth failed: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('Biometric auth failed: $e');
      return false;
    }
  }

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List? _unhex(String? hex) {
    if (hex == null || hex.length != 64) return null;
    return Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
  }
}

/// Stops the app from locking itself while it is in the background on
/// purpose: a file picker, the phone's unlock screen, a system dialog.
///
/// Without this, choosing a backup file would close the database midway.
class LockGuard {
  LockGuard._();

  static int _active = 0;
  static DateTime? _endedAt;

  static Future<T> run<T>(Future<T> Function() action) async {
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      _endedAt = DateTime.now();
    }
  }

  /// True while a guarded action runs, and for a moment after (the
  /// "resumed" event can arrive just after the action's result).
  static bool get suspended {
    if (_active > 0) return true;
    final ended = _endedAt;
    return ended != null && DateTime.now().difference(ended) < const Duration(seconds: 2);
  }
}

/// The app is locking: its screens are being closed and the database
/// closes right after. Forms use [active] to keep what was typed (instead
/// of discarding it as on Cancel), and hand their last database write to
/// [track] so it finishes before the database closes. After unlocking,
/// the form reopens with its data (see `PhotoRecovery`).
class SessionTeardown {
  SessionTeardown._();

  static bool _active = false;
  static final _pending = <Future<void>>[];

  static bool get active => _active;

  static void begin() => _active = true;

  /// Runs [work] before the database closes. Errors are logged, never thrown.
  static void track(Future<void> work) {
    _pending.add(work.catchError((Object e) => debugPrint('Could not keep the form for after unlocking: $e')));
  }

  /// Waits (briefly) for tracked work, then ends the teardown.
  static Future<void> finish({Duration timeout = const Duration(seconds: 3)}) async {
    final work = List.of(_pending);
    _pending.clear();
    try {
      await Future.wait(work).timeout(timeout);
    } catch (e) {
      debugPrint('Lock: unfinished work dropped: $e');
    } finally {
      _active = false;
    }
  }
}

