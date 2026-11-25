import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/services/photo_service.dart';
import '../providers/core_providers.dart';
import '../theme/app_palette.dart';
import 'common.dart';

/// Decrypted photo bytes (memory only; cached by PhotoService). Null when
/// the file is missing or can't be opened.
final photoBytesProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, path) async {
  try {
    return await ref.watch(photoServiceProvider).read(path);
  } catch (_) {
    return null;
  }
});

/// A stored (encrypted) photo, or a placeholder icon when there is none,
/// while it decrypts, or when the file is gone.
class PhotoThumb extends ConsumerWidget {
  const PhotoThumb({
    super.key,
    required this.path,
    required this.label,
    this.size = 48,
    this.fallbackIcon = Icons.image_outlined,
  });

  final String? path;

  /// What the photo shows, for screen readers ("Photo of Sugar").
  final String label;
  final double size;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final radius = BorderRadius.circular(size * 0.28);
    Widget box({required String semantics, Widget? child}) => Semantics(
          label: semantics,
          image: true,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: t.secondHigh, borderRadius: radius),
            child: ExcludeSemantics(child: child ?? Icon(fallbackIcon, color: t.onSecondMuted, size: size * 0.5)),
          ),
        );
    final p = path;
    if (p == null) return box(semantics: 'No photo for $label');
    final bytes = ref.watch(photoBytesProvider(p));
    return bytes.when(
      loading: () => box(semantics: 'Loading photo of $label', child: const SizedBox.shrink()),
      error: (_, _) => box(semantics: 'Photo of $label could not be opened'),
      data: (data) {
        if (data == null) return box(semantics: 'Photo of $label could not be opened');
        // Decode at display size, not full size, to keep lists light.
        final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
        return ClipRRect(
          borderRadius: radius,
          child: Image.memory(
            data,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: px,
            gaplessPlayback: true,
            semanticLabel: 'Photo of $label',
            errorBuilder: (_, _, _) => box(semantics: 'Photo of $label could not be opened'),
          ),
        );
      },
    );
  }
}

/// Photo picker for forms: preview, "Camera", "Gallery" and "Remove".
/// Permission problems show a message; the form keeps working without a photo.
///
/// [draft] is saved before the camera opens, so if Android closes the app
/// while the camera is up, the form and the photo come back on restart.
class PhotoField extends ConsumerStatefulWidget {
  const PhotoField({super.key, required this.path, required this.label, required this.onChanged, this.draft});

  final String? path;
  final String label;

  /// New path (null = removed).
  final ValueChanged<String?> onChanged;
  final PhotoDraft Function()? draft;

  @override
  ConsumerState<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends ConsumerState<PhotoField> {
  bool _busy = false;

  Future<void> _pick(PhotoSource source) async {
    final photos = ref.read(photoServiceProvider);
    setState(() => _busy = true);
    try {
      final draft = widget.draft;
      if (source == PhotoSource.camera && draft != null) {
        await photos.saveDraft(draft().copyWith(awaitingCamera: true));
      }
      final path = await photos.pick(source);
      if (path != null) widget.onChanged(path);
    } on PhotoAccessDenied catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not get the photo: $e', error: true);
    } finally {
      if (source == PhotoSource.camera) {
        try {
          await photos.cameraReturned();
        } catch (_) {
          // Only affects recovery after a crash.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.label.trim().isEmpty ? 'this item' : widget.label.trim();
    return Semantics(
      container: true,
      label: 'Photo for $name',
      child: Row(
        children: [
          PhotoThumb(path: widget.path, label: name, size: 88, fallbackIcon: Icons.add_a_photo_outlined),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : () => _pick(PhotoSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera', semanticsLabel: 'Take a photo with the camera'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : () => _pick(PhotoSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery', semanticsLabel: 'Choose a photo from the gallery'),
                ),
                if (widget.path != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _busy ? null : () => widget.onChanged(null),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove', semanticsLabel: 'Remove the photo'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tracks photos picked while a form is open, so cancelling the form
/// doesn't leave unused files behind.
class PickedPhotos {
  final _picked = <String>{};

  void add(String? path) {
    if (path != null) _picked.add(path);
  }

  /// Call when the form closes. [kept] is the photo that was saved (if any).
  void discardExcept(PhotoService photos, String? kept) {
    for (final p in _picked) {
      if (p != kept) photos.delete(p);
    }
    _picked.clear();
  }
}
