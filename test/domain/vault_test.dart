import 'dart:convert';
import 'dart:io';

import 'package:budgeting_app/domain/security/password_crypto.dart';
import 'package:budgeting_app/domain/security/vault.dart';
import 'package:budgeting_app/domain/services/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late Vault vault;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitaka_vault_test');
    // Low iteration counts keep the pure-Dart tests fast.
    vault = Vault(dir.path, passwordIterations: 1000, recoveryIterations: 1000);
  });

  tearDown(() => dir.delete(recursive: true));

  Future<VaultDraft> create([String password = 'correct horse']) async {
    final draft = await vault.prepare(password);
    await vault.save(draft);
    return draft;
  }

  test('prepare writes nothing until save', () async {
    await vault.prepare('correct horse');
    expect(await vault.exists(), isFalse);
  });

  test('right password returns the data key, wrong one throws', () async {
    final draft = await create();
    expect(await vault.unlockWithPassword('correct horse'), draft.dataKey);
    expect(() => vault.unlockWithPassword('wrong horse'), throwsA(isA<WrongSecretException>()));
  });

  test('vault file never contains the password, data key or recovery key', () async {
    final draft = await create();
    final text = await File('${dir.path}/${Vault.fileName}').readAsString();
    expect(text, isNot(contains('correct horse')));
    expect(text, isNot(contains(Vault.passphraseFor(draft.dataKey))));
    expect(text, isNot(contains(base64Encode(draft.dataKey))));
    expect(text, isNot(contains(Vault.normalizeRecoveryKey(draft.recoveryKey))));
  });

  test('recovery key resets the password and keeps the same data key', () async {
    final draft = await create();
    final key = await vault.resetPassword(
      recoveryKey: draft.recoveryKey.toLowerCase().replaceAll('-', ' '),
      newPassword: 'brand new pass',
    );
    expect(key, draft.dataKey);
    expect(await vault.verifyPassword('correct horse'), isFalse);
    expect(await vault.unlockWithPassword('brand new pass'), draft.dataKey);
  });

  test('wrong recovery key is rejected', () async {
    await create();
    expect(
      () => vault.resetPassword(recoveryKey: Vault.generateRecoveryKey(), newPassword: 'brand new pass'),
      throwsA(isA<WrongSecretException>()),
    );
  });

  test('change password and replace recovery key', () async {
    final draft = await create();
    await vault.changePassword(current: 'correct horse', next: 'second pass');
    expect(await vault.unlockWithPassword('second pass'), draft.dataKey);

    final newKey = await vault.replaceRecoveryKey(password: 'second pass');
    expect(
      () => vault.resetPassword(recoveryKey: draft.recoveryKey, newPassword: 'third pass'),
      throwsA(isA<WrongSecretException>()),
    );
    expect(await vault.resetPassword(recoveryKey: newKey, newPassword: 'third pass'), draft.dataKey);
  });

  test('short passwords are refused', () async {
    expect(Vault.validatePassword('short'), isNotNull);
    expect(() => vault.prepare('short'), throwsArgumentError);
  });

  test('recovery key format', () {
    final k = Vault.generateRecoveryKey();
    expect(k, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){5}$')));
  });

  group('BackupCrypto', () {
    test('round trip and wrong password', () async {
      const plain = '{"app":"pitaka","format":1,"tables":{}}';
      final enc = await BackupCrypto.encrypt(plain, 'backup pass', iterations: 1000);
      expect(BackupCrypto.isEncrypted(enc), isTrue);
      expect(BackupCrypto.isEncrypted(plain), isFalse);
      expect(enc, isNot(contains('tables')));
      expect(await BackupCrypto.decrypt(enc, 'backup pass'), plain);
      expect(() => BackupCrypto.decrypt(enc, 'nope nope'), throwsA(isA<WrongSecretException>()));
    });
  });
}
