import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Optional fingerprint / face unlock.
///
/// When turned on, the database key is kept in the operating system's
/// secure storage (Android Keystore / iOS Keychain), which only this app
/// can read, and the app asks for the fingerprint or face before using it.
/// The password always works too. Turning it off deletes the stored key.
///
/// The app never receives biometric data; the phone's OS checks it.
class AppLockService {
  AppLockService({LocalAuthentication? auth, FlutterSecureStorage? storage})
      : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const _keyName = 'pitaka_data_key_v1';

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
      return await _storage.containsKey(key: _keyName);
    } catch (e) {
      debugPrint('Secure storage unavailable: $e');
      return false;
    }
  }

  /// Asks for the fingerprint/face, then stores [dataKey]. Returns false if cancelled.
  Future<bool> enableBiometric(Uint8List dataKey) async {
    if (!await authenticateWithBiometrics()) return false;
    await _storage.write(key: _keyName, value: _hex(dataKey));
    return true;
  }

  Future<void> disableBiometric() async {
    try {
      await _storage.delete(key: _keyName);
    } catch (e) {
      debugPrint('Could not remove stored key: $e');
    }
  }

  /// Asks for the fingerprint/face and returns the stored data key, or null.
  Future<Uint8List?> unlockWithBiometrics() async {
    if (!await isBiometricEnabled()) return null;
    if (!await authenticateWithBiometrics()) return null;
    final hex = await _storage.read(key: _keyName);
    if (hex == null || hex.length != 64) return null;
    return Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
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
}
