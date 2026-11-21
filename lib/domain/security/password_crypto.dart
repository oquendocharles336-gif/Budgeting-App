import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Thrown when a password or recovery key doesn't open a sealed secret.
class WrongSecretException implements Exception {
  const WrongSecretException([this.message = 'Wrong password']);
  final String message;
  @override
  String toString() => message;
}

/// Bytes encrypted with a key derived from a password:
/// PBKDF2-HMAC-SHA256 (random 16-byte salt) -> AES-256-GCM.
///
/// GCM's authentication tag means a wrong password is detected reliably
/// instead of producing garbage.
class SealedSecret {
  const SealedSecret({
    required this.salt,
    required this.iterations,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final List<int> salt;
  final int iterations;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, Object?> toJson() => {
        'kdf': 'pbkdf2-hmac-sha256',
        'cipher': 'aes-256-gcm',
        'salt': base64Encode(salt),
        'iterations': iterations,
        'nonce': base64Encode(nonce),
        'ct': base64Encode(cipherText),
        'mac': base64Encode(mac),
      };

  factory SealedSecret.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Sealed secret is missing');
    try {
      return SealedSecret(
        salt: base64Decode(json['salt'] as String),
        iterations: json['iterations'] as int,
        nonce: base64Decode(json['nonce'] as String),
        cipherText: base64Decode(json['ct'] as String),
        mac: base64Decode(json['mac'] as String),
      );
    } on TypeError {
      throw const FormatException('Sealed secret is damaged');
    }
  }
}

class PasswordCrypto {
  PasswordCrypto._();

  static final _aes = AesGcm.with256bits();

  static List<int> randomBytes(int length) {
    final r = Random.secure();
    return List<int>.generate(length, (_) => r.nextInt(256));
  }

  static Future<SecretKey> deriveKey(String secret, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: secret, nonce: salt);

  static Future<SealedSecret> seal(
    List<int> clear,
    String secret, {
    required int iterations,
    List<int> aad = const [],
  }) async {
    final salt = randomBytes(16);
    final key = await deriveKey(secret, salt, iterations);
    final box = await _aes.encrypt(clear, secretKey: key, aad: aad);
    return SealedSecret(
      salt: salt,
      iterations: iterations,
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  /// Throws [WrongSecretException] if [secret] is wrong (or the data was tampered with).
  static Future<List<int>> open(SealedSecret sealed, String secret, {List<int> aad = const []}) async {
    final key = await deriveKey(secret, sealed.salt, sealed.iterations);
    try {
      return await _aes.decrypt(
        SecretBox(sealed.cipherText, nonce: sealed.nonce, mac: Mac(sealed.mac)),
        secretKey: key,
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw const WrongSecretException();
    }
  }
}
