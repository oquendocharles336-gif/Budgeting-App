import 'dart:convert';

import '../security/password_crypto.dart';
import 'backup_service.dart';

/// Wraps a JSON backup in a password-encrypted envelope
/// (PBKDF2-HMAC-SHA256 -> AES-256-GCM), so a backup file that leaks
/// (cloud drive, email, shared folder) can't be read without the password.
class BackupCrypto {
  BackupCrypto._();

  static const defaultIterations = 600000;
  static final _aad = utf8.encode('pitaka-backup-v1');

  static bool isEncrypted(String text) {
    try {
      final d = jsonDecode(text);
      return d is Map && d['app'] == 'pitaka' && d['encrypted'] == true;
    } on FormatException {
      return false;
    }
  }

  static Future<String> encrypt(String plainJson, String password, {int iterations = defaultIterations}) async {
    final sealed = await PasswordCrypto.seal(utf8.encode(plainJson), password, iterations: iterations, aad: _aad);
    return jsonEncode({
      'app': 'pitaka',
      'encrypted': true,
      'envelope': 1,
      'data': sealed.toJson(),
    });
  }

  /// Throws [WrongSecretException] for a wrong password and
  /// [BackupException] for a damaged file.
  static Future<String> decrypt(String text, String password) async {
    final Object? d;
    try {
      d = jsonDecode(text);
    } on FormatException {
      throw const BackupException('This file is not a valid backup (not JSON).');
    }
    if (d is! Map || d['app'] != 'pitaka' || d['encrypted'] != true) {
      throw const BackupException('This file is not an encrypted Pitaka backup.');
    }
    final SealedSecret sealed;
    try {
      sealed = SealedSecret.fromJson(d['data']);
    } on FormatException {
      throw const BackupException('Backup data is damaged.');
    }
    try {
      return utf8.decode(await PasswordCrypto.open(sealed, password, aad: _aad));
    } on WrongSecretException {
      throw const WrongSecretException('Wrong password for this backup');
    }
  }
}
