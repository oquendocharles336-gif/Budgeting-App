import 'dart:convert';

import '../../data/sources/photo_store.dart';

/// The form that was open when the camera started: which form, which
/// record (null = new) and what was typed. Saved before the camera opens,
/// so it can be put back if Android closes the app meanwhile.
class PhotoDraft {
  const PhotoDraft({
    required this.form,
    this.recordId,
    this.fields = const {},
    this.photoPath,
    this.awaitingCamera = false,
    this.interrupted = false,
  });

  static const inventoryForm = 'inventory';
  static const productForm = 'product';

  final String form;
  final int? recordId;
  final Map<String, String> fields;

  /// The photo the form showed before the camera opened.
  final String? photoPath;

  /// True from just before the camera opens until it returns. Still true
  /// at the next start = the app was closed while the camera was open.
  final bool awaitingCamera;

  /// True when the app locked while the form was open (the user left the
  /// app, or the camera took longer than the unlocked grace time). The
  /// form reopens after unlocking with what was typed.
  final bool interrupted;

  /// Reopened after the next start or unlock.
  bool get pending => awaitingCamera || interrupted;

  PhotoDraft copyWith({String? Function()? photoPath, bool? awaitingCamera, bool? interrupted}) => PhotoDraft(
        form: form,
        recordId: recordId,
        fields: fields,
        photoPath: photoPath != null ? photoPath() : this.photoPath,
        awaitingCamera: awaitingCamera ?? this.awaitingCamera,
        interrupted: interrupted ?? this.interrupted,
      );

  String toJson() => jsonEncode({
        'form': form,
        'recordId': recordId,
        'fields': fields,
        'photoPath': photoPath,
        'awaitingCamera': awaitingCamera,
        'interrupted': interrupted,
      });

  /// Null for missing or damaged text (never throws).
  static PhotoDraft? fromJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = jsonDecode(text);
      if (m is! Map || m['form'] is! String) return null;
      final fields = m['fields'];
      return PhotoDraft(
        form: m['form'] as String,
        recordId: m['recordId'] is int ? m['recordId'] as int : null,
        fields: fields is Map ? {for (final e in fields.entries) '${e.key}': '${e.value}'} : const {},
        photoPath: m['photoPath'] is String ? m['photoPath'] as String : null,
        awaitingCamera: m['awaitingCamera'] == true,
        interrupted: m['interrupted'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A form to reopen after the app restarted, with the recovered photo.
class RecoveredForm {
  const RecoveredForm({required this.draft, this.photoPath, this.message});
  final PhotoDraft draft;

  /// The new encrypted photo, or null if it couldn't be recovered.
  final String? photoPath;

  /// What to tell the user when the photo couldn't be recovered.
  final String? message;
}

/// Getting a camera photo back after Android closed the app (Android only;
/// `ImagePicker.retrieveLostData`). Dependencies are functions so the
/// flow is unit tested without plugins.
class PhotoRecovery {
  PhotoRecovery({
    required this.loadDraft,
    required this.saveDraft,
    required this.retrieveLost,
    required this.importPhoto,
    required this.discardWorkingCopy,
  });

  final Future<String?> Function() loadDraft;
  final Future<void> Function(String? json) saveDraft;
  final Future<LostPhoto> Function() retrieveLost;

  /// Compress + encrypt + save; returns the new photo's path.
  final Future<String> Function(String workingCopy) importPhoto;
  final Future<void> Function(String workingCopy) discardWorkingCopy;

  static const lockedMessage = 'Pitaka locked while you were editing. What you typed was kept.';

  /// Call on start-up (and when a photo form opens). Returns the form to
  /// reopen, or null when there is nothing to restore. Never throws.
  Future<RecoveredForm?> recover() async {
    PhotoDraft? draft;
    try {
      draft = PhotoDraft.fromJson(await loadDraft());
    } catch (_) {
      draft = null;
    }
    final lost = await retrieveLost();
    if (draft == null || !draft.pending) {
      // No form was waiting for the camera: nothing to attach a photo to,
      // so a stray working copy is just deleted.
      if (lost.path != null) await discardWorkingCopy(lost.path!);
      return null;
    }
    if (!draft.awaitingCamera) {
      // Locked while the form was open (camera not involved): reopen it
      // with what was typed and the photo it already had.
      if (lost.path != null) await discardWorkingCopy(lost.path!);
      final restored = draft.copyWith(interrupted: false);
      try {
        await saveDraft(restored.toJson());
      } catch (_) {
        // The form still reopens.
      }
      return RecoveredForm(draft: restored, message: lockedMessage);
    }
    String? photo;
    String? message;
    if (lost.path != null) {
      try {
        photo = await importPhoto(lost.path!);
      } catch (e) {
        message = 'The photo couldn\'t be saved. Please take it again.';
      } finally {
        await discardWorkingCopy(lost.path!);
      }
    } else if (lost.error != null) {
      message = lost.error;
    } else if (draft.interrupted) {
      // The app locked while the camera was open; the picture taken then
      // couldn't be saved into the closed data.
      message = 'Pitaka locked while the camera was open. Your form was kept; please take the photo again.';
    } else {
      // Cancelled in the camera, or Android didn't keep the photo.
      message = 'No photo was taken. Your form was kept.';
    }
    final restored =
        draft.copyWith(awaitingCamera: false, interrupted: false, photoPath: photo == null ? null : () => photo);
    try {
      await saveDraft(restored.toJson());
    } catch (_) {
      // The form still reopens; only a second restart would lose it.
    }
    return RecoveredForm(draft: restored, photoPath: photo, message: message);
  }
}
