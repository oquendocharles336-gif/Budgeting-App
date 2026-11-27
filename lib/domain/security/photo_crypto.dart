import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'password_crypto.dart';

class PhotoDecryptException implements Exception {
  const PhotoDecryptException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the photo key lives (a fake in tests).
abstract interface class PhotoKeyStore {
  /// The 32-byte key, created on first use.
  Future<List<int>> loadOrCreate();
  Future<void> delete();
}

/// The photo key in `flutter_secure_storage`, which on Android keeps it
/// encrypted by a key in the Android Keystore. It is never written to
/// SQLite or plain SharedPreferences, and never leaves the phone.
class SecurePhotoKeyStore implements PhotoKeyStore {
  SecurePhotoKeyStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static const keyName = 'pitaka_photo_key_v1';

  @override
  Future<List<int>> loadOrCreate() async {
    final saved = await _storage.read(key: keyName);
    if (saved != null) return base64Decode(saved);
    final key = PasswordCrypto.randomBytes(32);
    await _storage.write(key: keyName, value: base64Encode(key));
    return key;
  }

  @override
  Future<void> delete() => _storage.delete(key: keyName);
}

/// AES-256-GCM for photo files.
///
/// File layout: "PKPH" + version 1 (5 bytes) | nonce (12) | tag (16) | data.
/// The header is authenticated too, and a changed byte anywhere makes
/// decryption fail instead of showing a broken picture.
class PhotoCrypto {
  PhotoCrypto(this._keys);
  final PhotoKeyStore _keys;

  static const magic = [0x50, 0x4B, 0x50, 0x48, 0x01];
  static const _nonceLength = 12;
  static const _macLength = 16;
  static final _aes = AesGcm.with256bits();

  Future<SecretKey>? _key;

  /// One key load at a time, so two first photos can't create two keys.
  /// A load that fails (keystore busy right after unlocking, for example)
  /// is not kept: the next photo tries again instead of every photo and
  /// payment QR failing until the app is restarted.
  Future<SecretKey> _secret() {
    final cached = _key;
    if (cached != null) return cached;
    final loading = _keys.loadOrCreate().then(SecretKey.new);
    _key = loading;
    loading.then((_) {}, onError: (Object _) {
      if (identical(_key, loading)) _key = null;
    });
    return loading;
  }

  /// Drop the cached key (after "Delete all my data").
  void forgetKey() => _key = null;

  static bool isEncrypted(List<int> bytes) {
    if (bytes.length < magic.length + _nonceLength + _macLength) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  Future<Uint8List> encrypt(List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: await _secret(), aad: magic);
    return Uint8List.fromList([...magic, ...box.nonce, ...box.mac.bytes, ...box.cipherText]);
  }

  /// Throws [PhotoDecryptException] for a damaged file or a different key.
  Future<Uint8List> decrypt(List<int> data) async {
    if (!isEncrypted(data)) throw const PhotoDecryptException('Not an encrypted photo');
    var i = magic.length;
    final nonce = data.sublist(i, i += _nonceLength);
    final mac = data.sublist(i, i += _macLength);
    final cipherText = data.sublist(i);
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: await _secret(),
        aad: magic,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const PhotoDecryptException('This photo can\'t be opened with this phone\'s key');
    }
  }
}
