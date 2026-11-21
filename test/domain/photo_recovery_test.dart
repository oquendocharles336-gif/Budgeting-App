import 'package:budgeting_app/data/sources/photo_store.dart';
import 'package:budgeting_app/domain/services/photo_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lost-camera-photo path, without plugins: Android closed the app
/// while the camera was open, and `retrieveLostData` is called on restart.
void main() {
  late String? stored;
  late List<String> discarded;
  late List<String> imported;

  PhotoRecovery recovery({PhotoDraft? draft, LostPhoto lost = const LostPhoto.none(), bool importFails = false}) {
    stored = draft?.toJson();
    discarded = [];
    imported = [];
    return PhotoRecovery(
      loadDraft: () async => stored,
      saveDraft: (json) async => stored = json,
      retrieveLost: () async => lost,
      importPhoto: (path) async {
        if (importFails) throw Exception('disk full');
        imported.add(path);
        return '/app/business_photos/new.enc';
      },
      discardWorkingCopy: (path) async => discarded.add(path),
    );
  }

  const waiting = PhotoDraft(
    form: PhotoDraft.inventoryForm,
    recordId: 4,
    fields: {'name': 'Sugar', 'quantity': '100', 'unit': 'g'},
    awaitingCamera: true,
  );

  test('a lost photo is encrypted, attached to the form, and the plain copy deleted', () async {
    final r = await recovery(draft: waiting, lost: const LostPhoto(path: '/cache/img.jpg')).recover();
    expect(r, isNotNull);
    expect(r!.photoPath, '/app/business_photos/new.enc');
    expect(r.draft.form, PhotoDraft.inventoryForm);
    expect(r.draft.recordId, 4);
    expect(r.draft.fields['name'], 'Sugar');
    expect(r.message, isNull);
    expect(imported, ['/cache/img.jpg']);
    expect(discarded, ['/cache/img.jpg']);
    // Not waiting any more, so a second start doesn't reopen it again.
    expect(PhotoDraft.fromJson(stored)!.awaitingCamera, isFalse);
  });

  test('cancelled in the camera: the form comes back without a photo', () async {
    final r = await recovery(draft: waiting).recover();
    expect(r!.photoPath, isNull);
    expect(r.message, contains('No photo'));
  });

  test('camera permission denied: the form comes back with the reason', () async {
    final r = await recovery(draft: waiting, lost: const LostPhoto(error: 'Camera access is off.')).recover();
    expect(r!.photoPath, isNull);
    expect(r.message, 'Camera access is off.');
  });

  test('saving the recovered photo fails: no crash, plain copy still deleted', () async {
    final r = await recovery(draft: waiting, lost: const LostPhoto(path: '/cache/img.jpg'), importFails: true).recover();
    expect(r!.photoPath, isNull);
    expect(r.message, isNotNull);
    expect(discarded, ['/cache/img.jpg']);
  });

  test('no form was waiting: nothing reopens and a stray file is deleted', () async {
    final r = await recovery(lost: const LostPhoto(path: '/cache/stray.jpg')).recover();
    expect(r, isNull);
    expect(discarded, ['/cache/stray.jpg']);
    expect(imported, isEmpty);
  });

  test('the camera returned normally (not waiting): nothing to do', () async {
    final r = await recovery(draft: waiting.copyWith(awaitingCamera: false)).recover();
    expect(r, isNull);
  });

  test('a damaged draft is ignored', () {
    expect(PhotoDraft.fromJson('{not json'), isNull);
    expect(PhotoDraft.fromJson(null), isNull);
  });
}
