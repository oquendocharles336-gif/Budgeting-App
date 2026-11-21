import 'dart:convert';

import 'package:budgeting_app/domain/update/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String release({
    Object? tag = 'v1.2.0',
    Object? page = 'https://github.com/me/r/releases/tag/v1.2.0',
    List<Map<String, Object?>>? assets,
    Object? body = '## Changes\n- Faster charts\n*   Fixed   a **crash**  \n\n- [Link](https://x.y) text',
    bool draft = false,
    bool pre = false,
  }) =>
      jsonEncode({
        'tag_name': tag,
        'name': 'Pitaka 1.2.0',
        'html_url': page,
        'draft': draft,
        'prerelease': pre,
        'published_at': '2026-12-01T08:00:00Z',
        'body': body,
        'assets': assets ??
            [
              {'name': 'notes.txt', 'browser_download_url': 'https://github.com/me/r/releases/download/v1.2.0/notes.txt'},
              {'name': 'pitaka-1.2.0.apk', 'browser_download_url': 'https://github.com/me/r/releases/download/v1.2.0/pitaka-1.2.0.apk'},
            ],
      });

  AppVersion v(String s) => AppVersion.tryParse(s)!;

  group('semantic versions', () {
    test('a leading v is ignored', () {
      expect(v('v1.2.0'), v('1.2.0'));
      expect(v('V2'), v('2.0.0'));
    });

    test('compared part by part, as numbers', () {
      expect(v('1.10.0') > v('1.9.9'), isTrue);
      expect(v('2.0.0') > v('1.99.99'), isTrue);
      expect(v('1.2.1') > v('1.2.0'), isTrue);
    });

    test('pre-releases are older than the release; build metadata is ignored', () {
      expect(v('1.2.0-beta.2') < v('1.2.0'), isTrue);
      expect(v('1.2.0-beta.2') > v('1.2.0-beta.1'), isTrue);
      expect(v('1.2.0-alpha') < v('1.2.0-beta'), isTrue);
      expect(v('1.2.0+7'), v('1.2.0+3'));
    });

    test('rejects text that is not a version', () {
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse(null), isNull);
    });
  });

  group('GitHub release', () {
    test('reads the tag, the APK asset and the notes', () {
      final r = ReleaseInfo.parseGitHub(release());
      expect(r.version, v('1.2.0'));
      expect(r.tag, 'v1.2.0');
      expect(r.isApk, isTrue);
      expect(r.downloadUrl.path, endsWith('pitaka-1.2.0.apk'));
      expect(r.notes, ['Changes', 'Faster charts', 'Fixed a crash', 'Link text']);
      expect(r.releasedAt, DateTime.utc(2026, 12, 1, 8).toLocal());
    });

    test('no APK: the download link is the release page', () {
      final r = ReleaseInfo.parseGitHub(release(assets: const []));
      expect(r.isApk, isFalse);
      expect(r.downloadUrl.toString(), 'https://github.com/me/r/releases/tag/v1.2.0');
    });

    test('rejects anything unexpected instead of showing it', () {
      expect(() => ReleaseInfo.parseGitHub('not json'), throwsFormatException);
      expect(() => ReleaseInfo.parseGitHub('[]'), throwsFormatException);
      expect(() => ReleaseInfo.parseGitHub(release(tag: 'latest')), throwsFormatException);
      expect(() => ReleaseInfo.parseGitHub(release(tag: null)), throwsFormatException);
      expect(() => ReleaseInfo.parseGitHub(release(page: 'http://insecure.example')), throwsFormatException);
      expect(() => ReleaseInfo.parseGitHub(release(draft: true)), throwsFormatException);
      expect(() => ReleaseInfo.parseGitHub(release(pre: true)), throwsFormatException);
    });

    test('long notes are cut, and at most 30 are kept', () {
      final r = ReleaseInfo.parseGitHub(release(body: List.filled(40, '- ${'x' * 400}').join('\n')));
      expect(r.notes, hasLength(ReleaseInfo.maxNotes));
      expect(r.notes.first.length, ReleaseInfo.maxNoteLength + 1);
    });
  });

  group('when to prompt', () {
    final r = ReleaseInfo.parseGitHub(release(tag: 'v1.2.0'));

    test('newer release: update available', () {
      expect(UpdatePolicy.isNewer(installed: '1.1.0', release: r), isTrue);
      expect(UpdatePolicy.shouldPrompt(installed: '1.1.0', release: r), isTrue);
    });

    test('same or newer installed: up to date', () {
      expect(UpdatePolicy.isNewer(installed: '1.2.0', release: r), isFalse);
      expect(UpdatePolicy.isNewer(installed: '1.3.0', release: r), isFalse);
    });

    test('a skipped version isn\'t shown again, a later one is', () {
      expect(UpdatePolicy.shouldPrompt(installed: '1.1.0', release: r, skippedVersion: '1.2.0'), isFalse);
      expect(UpdatePolicy.shouldPrompt(installed: '1.1.0', release: r, skippedVersion: '1.1.5'), isTrue);
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
      expect(WhatsNew.since(all, lastSeen: '1.0.0', current: '1.2.0').map((e) => e.version), ['1.2.0', '1.1.0']);
    });

    test('only when the installed version is higher than the one seen', () {
      expect(WhatsNew.shouldShow(lastSeen: '1.1.0', current: '1.2.0'), isTrue);
      expect(WhatsNew.shouldShow(lastSeen: '1.2.0', current: '1.2.0'), isFalse);
      expect(WhatsNew.shouldShow(lastSeen: '1.3.0', current: '1.2.0'), isFalse);
    });

    test('nothing on a fresh install', () {
      expect(WhatsNew.since(all, lastSeen: null, current: '1.2.0'), isEmpty);
    });

    test('old build-number records map to their version', () {
      expect(WhatsNew.versionForBuild(all, 2), '1.1.0');
      expect(WhatsNew.versionForBuild(all, 9), isNull);
    });
  });
}
