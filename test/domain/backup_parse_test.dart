import 'dart:convert';

import 'package:budgeting_app/data/db/migrations.dart';
import 'package:budgeting_app/domain/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String backup({Object? photos, int format = 2, Object? tables}) => jsonEncode({
        'app': 'pitaka',
        'format': format,
        'schemaVersion': Migrations.latestVersion,
        'tables': tables ??
            {
              'stock_movements': [
                {'id': 1, 'item_id': 1, 'change': 5, 'reason': 'restock', 'date': 1, 'created_at': 1},
              ],
              'capital_entries': <Object>[],
            },
        'photos': ?photos,
      });

  test('reads tables (stock and capital ledgers included) and photos', () {
    final d = BackupService.parse(backup(photos: {'1_2.enc': base64Encode([1, 2, 3])}));
    expect(d.count('stock_movements'), 1);
    expect(d.tables.containsKey('capital_entries'), isTrue);
    expect(d.photos.keys, ['1_2.enc']);
  });

  test('old backups without photos still open', () {
    expect(BackupService.parse(backup(format: 1)).photos, isEmpty);
  });

  test('photo names that point elsewhere are rejected', () {
    expect(() => BackupService.parse(backup(photos: {'../evil.enc': 'AA=='})), throwsA(isA<BackupException>()));
    expect(() => BackupService.parse(backup(photos: {'a/b.enc': 'AA=='})), throwsA(isA<BackupException>()));
  });

  test('damaged tables are rejected before anything is restored', () {
    expect(() => BackupService.parse(backup(tables: {'orders': 'oops'})), throwsA(isA<BackupException>()));
    expect(() => BackupService.parse('not json'), throwsA(isA<BackupException>()));
  });

  test('backups from a newer app version are refused', () {
    final newer = jsonEncode({'app': 'pitaka', 'format': 2, 'schemaVersion': Migrations.latestVersion + 1, 'tables': {}});
    expect(() => BackupService.parse(newer), throwsA(isA<BackupException>()));
  });
}
