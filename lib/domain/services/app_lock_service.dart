import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/repositories/settings_repository.dart';

/// Optional PIN and biometric lock.
///
/// The PIN is never stored. Only a salted SHA-256 hash is kept in the local
/// database. (This keeps casual snoopers out; it is not bank-grade
/// encryption of the data itself.)
class AppLockService {
  AppLockService(this._settings, {LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final SettingsRepository _settings;
  final LocalAuthentication _auth;

  static final _pinFormat = RegExp(r'^\d{4,6}$');

  static bool isValidPin(String pin) => _pinFormat.hasMatch(pin);

  Future<bool> isPinSet() async => (await _settings.get(SettingsRepository.pinHash)) != null;

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4 to 6 digits');
    final rnd = Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _settings.set(SettingsRepository.pinSalt, salt);
    await _settings.set(SettingsRepository.pinHash, _hash(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final hash = await _settings.get(SettingsRepository.pinHash);
    final salt = await _settings.get(SettingsRepository.pinSalt);
    if (hash == null || salt == null) return false;
    return _hash(pin, salt) == hash;
  }

  Future<void> removeLock() async {
    await _settings.remove(SettingsRepository.pinHash);
    await _settings.remove(SettingsRepository.pinSalt);
    await _settings.remove(SettingsRepository.biometricEnabled);
  }

  Future<bool> isBiometricEnabled() async =>
      (await _settings.get(SettingsRepository.biometricEnabled)) == '1';

  Future<void> setBiometricEnabled(bool enabled) =>
      _settings.set(SettingsRepository.biometricEnabled, enabled ? '1' : '0');

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

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
