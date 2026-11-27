import 'dart:typed_data';

import 'package:budgeting_app/data/repositories/business_repositories.dart';
import 'package:budgeting_app/data/repositories/settings_repository.dart';
import 'package:budgeting_app/data/sources/photo_store.dart';
import 'package:budgeting_app/domain/security/password_crypto.dart';
import 'package:budgeting_app/domain/security/photo_crypto.dart';
import 'package:budgeting_app/domain/services/photo_service.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryKeys implements PhotoKeyStore {
  List<int>? key;

  @override
  Future<List<int>> loadOrCreate() async => key ??= PasswordCrypto.randomBytes(32);

  @override
  Future<void> delete() async => key = null;
}

/// Photo files in memory. Each pick returns a new picker copy whose bytes
/// are the next entry of [picks] (null = the user cancelled).
class FakeStore implements PhotoStore {
  final files = <String, Uint8List>{};
  final deleted = <String>[];
  final picks = <List<int>?>[];
  var _n = 0;

  @override
  Future<String?> pickWorkingCopy(PhotoSource source) async {
    final next = picks.removeAt(0);
    if (next == null) return null;
    final path = '/cache/pick${_n++}.jpg';
    files[path] = Uint8List.fromList(next);
    return path;
  }

  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('missing $path'));

  @override
  Future<String> writeEncrypted(Uint8List bytes, {bool staging = false}) async {
    final path = '/photos/${_n++}.enc';
    files[path] = bytes;
    return path;
  }

  @override
  Future<void> deleteWorkingCopy(String path) async => files.remove(path);

  @override
  Future<void> delete(String? path) async {
    if (path == null) return;
    deleted.add(path);
    files.remove(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettings implements SettingsRepository {
  final values = <String, String>{};
  bool failNextSet = false;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    if (failNextSet) {
      failNextSet = false;
      throw Exception('database is locked');
    }
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedProducts implements ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeStore store;
  late FakeSettings settings;
  late PhotoService photos;
  final qrA = List<int>.filled(64, 1);
  final qrB = List<int>.filled(64, 2);
  final key = SettingsRepository.paymentQrKey('maya');

  setUp(() {
    store = FakeStore();
    settings = FakeSettings();
    final keys = MemoryKeys();
    photos = PhotoService(
      store: store,
      crypto: PhotoCrypto(keys),
      keys: keys,
      inventory: UnusedInventory(),
      products: UnusedProducts(),
      settings: settings,
    );
  });

  test('a saved QR can be replaced: new path saved, old file deleted, new picture shown', () async {
    store.picks.addAll([qrA, qrB]);
    final first = await photos.setPaymentQr('maya');
    expect(await photos.read(first!), qrA);

    final second = await photos.setPaymentQr('maya');
    expect(second, isNot(first));
    expect(settings.values[key], second);
    expect(await photos.paymentQrPath('maya'), second);
    expect(store.deleted, contains(first));
    // The new bytes, not a cached copy of the first QR.
    expect(await photos.read(second!), qrB);
    await expectLater(photos.read(first), throwsStateError);
  });

  test('cancelling the picker keeps the current QR', () async {
    store.picks.addAll([qrA, null]);
    final first = await photos.setPaymentQr('maya');
    expect(await photos.setPaymentQr('maya'), isNull);
    expect(settings.values[key], first);
    expect(store.deleted, isEmpty);
  });

  test('a failed save keeps the old QR and removes the unused new file', () async {
    store.picks.addAll([qrA, qrB]);
    final first = await photos.setPaymentQr('maya');
    settings.failNextSet = true;
    await expectLater(photos.setPaymentQr('maya'), throwsException);
    expect(settings.values[key], first);
    expect(await photos.read(first!), qrA);
    expect(store.files.keys.where((p) => p.endsWith('.enc')), [first]);
  });

  test('remove, then upload again', () async {
    store.picks.addAll([qrA, qrB]);
    final first = await photos.setPaymentQr('maya');
    await photos.removePaymentQr('maya');
    expect(await photos.paymentQrPath('maya'), isNull);
    expect(store.deleted, [first]);
    final again = await photos.setPaymentQr('maya');
    expect(await photos.paymentQrPath('maya'), again);
    expect(await photos.read(again!), qrB);
  });

  test('each payment method keeps its own QR', () async {
    store.picks.addAll([qrA, qrB]);
    final maya = await photos.setPaymentQr('maya');
    final bdo = await photos.setPaymentQr('bdo');
    expect(await photos.paymentQrPath('maya'), maya);
    expect(await photos.paymentQrPath('bdo'), bdo);
    expect(store.deleted, isEmpty);
  });
}
