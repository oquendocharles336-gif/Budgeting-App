import 'dart:convert';

import 'package:budgeting_app/domain/update/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String feed({
    Object? version = '1.2.0',
    Object? build = 3,
    Object? min,
    Object? url = 'https://github.com/me/r/releases/download/v1.2.0/pitaka.apk',
    Object? notes,
    Object? sha,
  }) =>
      jsonEncode({
        'latestVersion': version,
        'latestBuild': build,
        'minSupportedBuild': ?min,
        'apkUrl': url,
        'notes': notes ?? ['Faster charts', '  Fixed   a crash  '],
        'sha256': ?sha,
        'releasedAt': '2026-12-01',
      });

  group('version file', () {
    test('reads a good file and cleans the notes', () {
      final r = ReleaseInfo.parse(feed());
      expect(r.version, '1.2.0');
      expect(r.build, 3);
      expect(r.apkUrl.host, 'github.com');
      expect(r.notes, ['Faster charts', 'Fixed a crash']);
      expect(r.releasedAt, DateTime(2026, 12, 1));
    });

    test('rejects anything unexpected instead of showing it', () {
      expect(() => ReleaseInfo.parse('not json'), throwsFormatException);
      expect(() => ReleaseInfo.parse(feed(version: 'v1.2')), throwsFormatException);
      expect(() => ReleaseInfo.parse(feed(build: 0)), throwsFormatException);
      expect(() => ReleaseInfo.parse(feed(build: '3')), throwsFormatException);
      expect(() => ReleaseInfo.parse(feed(url: 'http://insecure.example/app.apk')), throwsFormatException);
      expect(() => ReleaseInfo.parse(feed(url: 'javascript:alert(1)')), throwsFormatException);
      expect(() => ReleaseInfo.parse(feed(notes: 'one string')), throwsFormatException);
    });

    test('long notes are cut, and at most 30 are kept', () {
      final r = ReleaseInfo.parse(feed(notes: [for (var i = 0; i < 40; i++) 'x' * 400]));
      expect(r.notes, hasLength(ReleaseInfo.maxNotes));
      expect(r.notes.first.length, ReleaseInfo.maxNoteLength + 1);
    });

    test('a bad checksum is dropped, a good one kept', () {
      expect(ReleaseInfo.parse(feed(sha: 'abc')).sha256, isNull);
      expect(ReleaseInfo.parse(feed(sha: 'A' * 64)).sha256, 'a' * 64);
    });
  });

  group('when to prompt', () {
    final release = ReleaseInfo.parse(feed(build: 3));

    test('newer build: optional update', () {
      expect(UpdatePolicy.urgency(currentBuild: 2, release: release), UpdateUrgency.optional);
      expect(UpdatePolicy.shouldPrompt(currentBuild: 2, release: release), isTrue);
    });

    test('same or newer installed: nothing', () {
      expect(UpdatePolicy.urgency(currentBuild: 3, release: release), UpdateUrgency.none);
      expect(UpdatePolicy.shouldPrompt(currentBuild: 4, release: release), isFalse);
    });

    test('a skipped version isn\'t shown again, a later one is', () {
      expect(UpdatePolicy.shouldPrompt(currentBuild: 2, release: release, skippedBuild: 3), isFalse);
      expect(UpdatePolicy.shouldPrompt(currentBuild: 2, release: release, skippedBuild: 2), isTrue);
    });

    test('below minSupportedBuild: required, even if skipped', () {
      final r = ReleaseInfo.parse(feed(build: 5, min: 4));
      expect(UpdatePolicy.urgency(currentBuild: 3, release: r), UpdateUrgency.required);
      expect(UpdatePolicy.shouldPrompt(currentBuild: 3, release: r, skippedBuild: 5), isTrue);
    });

    test('automatic check at most once a day', () {
      final now = DateTime(2026, 11, 21, 12);
      const day = Duration(hours: 24);
      expect(UpdatePolicy.checkDue(lastCheck: null, now: now, every: day), isTrue);
      expect(UpdatePolicy.checkDue(lastCheck: now.subtract(const Duration(hours: 3)), now: now, every: day), isFalse);
      expect(UpdatePolicy.checkDue(lastCheck: now.subtract(const Duration(hours: 25)), now: now, every: day), isTrue);
      // Clock moved back: check again rather than wait.
      expect(UpdatePolicy.checkDue(lastCheck: now.add(const Duration(days: 2)), now: now, every: day), isTrue);
    });
  });

  group('what\'s new after updating', () {
    const all = [
      ChangelogEntry(version: '1.2.0', build: 3, notes: ['c']),
      ChangelogEntry(version: '1.1.0', build: 2, notes: ['b']),
      ChangelogEntry(version: '1.0.0', build: 1, notes: ['a']),
    ];

    test('shows every version since the last one seen, newest first', () {
      expect(WhatsNew.since(all, lastSeenBuild: 1, currentBuild: 3).map((e) => e.build), [3, 2]);
    });

    test('nothing on a fresh install or when already seen', () {
      expect(WhatsNew.since(all, lastSeenBuild: null, currentBuild: 3), isEmpty);
      expect(WhatsNew.since(all, lastSeenBuild: 3, currentBuild: 3), isEmpty);
    });

    test('versions compare part by part', () {
      expect(AppVersion.tryParse('1.10.0')!.compareTo(AppVersion.tryParse('1.9.9')!), greaterThan(0));
      expect(AppVersion.tryParse('1.2'), isNull);
    });
  });
}
