import 'package:budgeting_app/domain/security/password_crypto.dart';
import 'package:budgeting_app/domain/security/photo_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryKeys implements PhotoKeyStore {
  List<int>? key;
  var created = 0;

  @override
  Future<List<int>> loadOrCreate() async {
    if (key == null) created++;
    return key ??= PasswordCrypto.randomBytes(32);
  }

  @override
  Future<void> delete() async => key = null;
}

/// Fails the first [failures] loads, like a keystore that isn't ready.
class FlakyKeys extends MemoryKeys {
  FlakyKeys(this.failures);
  int failures;

  @override
  Future<List<int>> loadOrCreate() async {
    if (failures > 0) {
      failures--;
      throw Exception('keystore not ready');
    }
    return super.loadOrCreate();
  }
}

void main() {
  final photo = List<int>.generate(5000, (i) => (i * 31) % 256); // stands in for JPEG bytes

  test('encrypt then decrypt gives the same bytes; the file is not plain', () async {
    final crypto = PhotoCrypto(MemoryKeys());
    final enc = await crypto.encrypt(photo);
    expect(PhotoCrypto.isEncrypted(enc), isTrue);
    expect(PhotoCrypto.isEncrypted(photo), isFalse);
    expect(enc.sublist(5, 105), isNot(photo.sublist(0, 100)));
    expect(await crypto.decrypt(enc), photo);
  });

  test('a changed byte is detected (AES-GCM tag)', () async {
    final crypto = PhotoCrypto(MemoryKeys());
    final enc = await crypto.encrypt(photo);
    enc[enc.length - 1] ^= 0x01;
    await expectLater(crypto.decrypt(enc), throwsA(isA<PhotoDecryptException>()));
  });

  test('another key (another phone, or after "Delete all") can\'t open it', () async {
    final enc = await PhotoCrypto(MemoryKeys()).encrypt(photo);
    await expectLater(PhotoCrypto(MemoryKeys()).decrypt(enc), throwsA(isA<PhotoDecryptException>()));
  });

  test('the key is created once and reused', () async {
    final keys = MemoryKeys();
    final crypto = PhotoCrypto(keys);
    await Future.wait([crypto.encrypt(photo), crypto.encrypt(photo)]);
    expect(keys.created, 1);
  });

  test('each encryption uses a fresh nonce', () async {
    final crypto = PhotoCrypto(MemoryKeys());
    final a = await crypto.encrypt(photo);
    final b = await crypto.encrypt(photo);
    expect(a.sublist(5, 17), isNot(b.sublist(5, 17)));
  });

  test('a failed key load is retried on the next photo (not cached)', () async {
    final keys = FlakyKeys(1);
    final crypto = PhotoCrypto(keys);
    await expectLater(crypto.encrypt(photo), throwsException);
    final enc = await crypto.encrypt(photo);
    expect(await crypto.decrypt(enc), photo);
    expect(keys.created, 1);
  });
}
