import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'password_crypto.dart';

/// Result of [Vault.prepare]: the new data key and the one-time recovery
/// key, before anything is written to disk.
class VaultDraft {
  const VaultDraft({required this.dataKey, required this.recoveryKey, required this.json});

  /// Random 256-bit key that encrypts the database. Never stored in clear.
  final Uint8List dataKey;

  /// Shown to the user once ("XXXX-XXXX-..."). Never stored in clear.
  final String recoveryKey;
  final Map<String, Object?> json;
}

/// The small file that lets the user's password unlock the database.
///
/// How it works:
///  * The database is encrypted (SQLCipher) with a random 256-bit data key.
///  * The vault file holds that data key twice, each copy encrypted with
///    AES-256-GCM: once under a key derived from the password, once under a
///    key derived from the recovery key (both PBKDF2-HMAC-SHA256).
///  * Neither the password, the recovery key nor the data key is ever
///    written to disk in clear, and nothing leaves the phone. Without the
///    password or recovery key the database file is unreadable, including
///    to the developer.
///
/// Changing the password only re-encrypts the small data-key copy; the
/// database itself is not rewritten.
class Vault {
  Vault(this.directory, {this.passwordIterations = 600000, this.recoveryIterations = 100000});

  final String directory;

  /// OWASP's 2023 recommendation for PBKDF2-HMAC-SHA256.
  final int passwordIterations;

  /// The recovery key is ~120 random bits, so it needs far less stretching.
  final int recoveryIterations;

  static const fileName = 'pitaka_vault.json';
  static const minPasswordLength = 8;

  // Binds each sealed copy to its purpose.
  static final _aadPassword = utf8.encode('pitaka-vault-v1:password');
  static final _aadRecovery = utf8.encode('pitaka-vault-v1:recovery');

  // No 0/O or 1/I so it's easy to copy by hand. 32 symbols = 5 bits each.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _recoveryLength = 24;

  File get _file => File(p.join(directory, fileName));

  Future<bool> exists() => _file.exists();

  static const minPinLength = 6;
  static const maxPinLength = 12;

  /// Accepts a numeric PIN (6-12 digits, not 000000 / 123456 style) or a
  /// password of at least [minPasswordLength] characters.
  static String? validatePassword(String password) {
    if (RegExp(r'^\d+$').hasMatch(password)) {
      if (password.length < minPinLength) return 'A PIN needs at least $minPinLength digits';
      if (password.length > maxPinLength) return 'A PIN can have at most $maxPinLength digits';
      if (_isTrivialPin(password)) return 'That PIN is too easy to guess';
      return null;
    }
    if (password.length < minPasswordLength) {
      return 'Use a PIN of $minPinLength+ digits or a password of $minPasswordLength+ characters';
    }
    return null;
  }

  /// Same digit repeated, or a straight run up or down (123456, 987654).
  static bool _isTrivialPin(String pin) {
    final d = pin.codeUnits.map((c) => c - 48).toList();
    if (d.every((x) => x == d.first)) return true;
    var up = true, down = true;
    for (var i = 1; i < d.length; i++) {
      if (d[i] != (d[i - 1] + 1) % 10) up = false;
      if (d[i] != (d[i - 1] + 9) % 10) down = false;
    }
    return up || down;
  }

  static String generateRecoveryKey() {
    final r = Random.secure();
    final chars = List.generate(_recoveryLength, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
    return [for (var i = 0; i < chars.length; i += 4) chars.substring(i, i + 4)].join('-');
  }

  /// Accepts lower case, spaces and dashes.
  static String normalizeRecoveryKey(String input) => input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// SQLCipher passphrase for a data key (64 hex characters).
  static String passphraseFor(List<int> dataKey) =>
      dataKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Creates a new data key and recovery key. Nothing is saved until
  /// [save] is called, so a failed database set-up leaves no vault behind.
  Future<VaultDraft> prepare(String password) async {
    final error = validatePassword(password);
    if (error != null) throw ArgumentError(error);
    final dataKey = Uint8List.fromList(PasswordCrypto.randomBytes(32));
    final recoveryKey = generateRecoveryKey();
    final json = <String, Object?>{
      'app': 'pitaka',
      'version': 1,
      'password': (await PasswordCrypto.seal(dataKey, password, iterations: passwordIterations, aad: _aadPassword)).toJson(),
      'recovery': (await PasswordCrypto.seal(
        dataKey,
        normalizeRecoveryKey(recoveryKey),
        iterations: recoveryIterations,
        aad: _aadRecovery,
      ))
          .toJson(),
    };
    return VaultDraft(dataKey: dataKey, recoveryKey: recoveryKey, json: json);
  }

  /// For the phone-lock method: the data key is sealed only under the
  /// recovery key here (the phone keystore holds the everyday copy), so
  /// there is no in-app password until the user sets one.
  Future<VaultDraft> prepareWithoutPassword() async {
    final dataKey = Uint8List.fromList(PasswordCrypto.randomBytes(32));
    final recoveryKey = generateRecoveryKey();
    final json = <String, Object?>{
      'app': 'pitaka',
      'version': 1,
      'recovery': (await PasswordCrypto.seal(
        dataKey,
        normalizeRecoveryKey(recoveryKey),
        iterations: recoveryIterations,
        aad: _aadRecovery,
      ))
          .toJson(),
    };
    return VaultDraft(dataKey: dataKey, recoveryKey: recoveryKey, json: json);
  }

  Future<void> save(VaultDraft draft) => _write(draft.json);

  /// Whether an in-app PIN / password can unlock the data.
  Future<bool> hasPassword() async => (await _read())['password'] != null;

  /// Seals the (already unlocked) data key under [password]: used when
  /// switching to the in-app PIN, or when the phone lock was removed.
  Future<void> setPassword(Uint8List dataKey, String password) async {
    final error = validatePassword(password);
    if (error != null) throw ArgumentError(error);
    final json = await _read();
    json['password'] =
        (await PasswordCrypto.seal(dataKey, password, iterations: passwordIterations, aad: _aadPassword)).toJson();
    await _write(json);
  }

  /// Switching to the phone lock: the old PIN stops working. The recovery
  /// key keeps working.
  Future<void> removePassword() async {
    final json = await _read();
    json.remove('password');
    await _write(json);
  }

  /// Returns the data key. Throws [WrongSecretException] for a wrong password.
  Future<Uint8List> unlockWithPassword(String password) async {
    final json = await _read();
    return Uint8List.fromList(
      await PasswordCrypto.open(SealedSecret.fromJson(json['password']), password, aad: _aadPassword),
    );
  }

  Future<bool> verifyPassword(String password) async {
    try {
      await unlockWithPassword(password);
      return true;
    } on WrongSecretException {
      return false;
    }
  }

  /// Forgot-password flow: opens the data key with the recovery key and
  /// sets [newPassword]. The recovery key keeps working.
  Future<Uint8List> resetPassword({required String recoveryKey, required String newPassword}) async {
    final error = validatePassword(newPassword);
    if (error != null) throw ArgumentError(error);
    final json = await _read();
    final List<int> dataKey;
    try {
      dataKey = await PasswordCrypto.open(
        SealedSecret.fromJson(json['recovery']),
        normalizeRecoveryKey(recoveryKey),
        aad: _aadRecovery,
      );
    } on WrongSecretException {
      throw const WrongSecretException('That recovery key is not right');
    }
    json['password'] =
        (await PasswordCrypto.seal(dataKey, newPassword, iterations: passwordIterations, aad: _aadPassword)).toJson();
    await _write(json);
    return Uint8List.fromList(dataKey);
  }

  Future<void> changePassword({required String current, required String next}) async {
    final error = validatePassword(next);
    if (error != null) throw ArgumentError(error);
    final dataKey = await unlockWithPassword(current);
    final json = await _read();
    json['password'] =
        (await PasswordCrypto.seal(dataKey, next, iterations: passwordIterations, aad: _aadPassword)).toJson();
    await _write(json);
  }

  /// Replaces the recovery key (the old one stops working). Returns the new one.
  Future<String> replaceRecoveryKey({required String password}) async =>
      replaceRecoveryKeyWith(await unlockWithPassword(password));

  /// Same, with the data key of the open session (phone-lock method, after
  /// the phone confirmed it's the owner).
  Future<String> replaceRecoveryKeyWith(List<int> dataKey) async {
    final json = await _read();
    final recoveryKey = generateRecoveryKey();
    json['recovery'] = (await PasswordCrypto.seal(
      dataKey,
      normalizeRecoveryKey(recoveryKey),
      iterations: recoveryIterations,
      aad: _aadRecovery,
    ))
        .toJson();
    await _write(json);
    return recoveryKey;
  }

  Future<Map<String, Object?>> _read() async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await _file.readAsString());
    } on FormatException {
      throw const FormatException('The account file is damaged');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'pitaka') {
      throw const FormatException('The account file is damaged');
    }
    return decoded;
  }

  /// Write-then-rename, so a crash never leaves a half-written vault.
  Future<void> _write(Map<String, Object?> json) async {
    await Directory(directory).create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(_file.path);
  }
}
