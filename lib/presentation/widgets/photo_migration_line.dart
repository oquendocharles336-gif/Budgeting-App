import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers/photo_migration_provider.dart';
import '../theme/app_palette.dart';

/// Inline progress (not a banner) while old photos are being encrypted.
class PhotoMigrationLine extends ConsumerWidget {
  const PhotoMigrationLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(photoMigrationProvider);
    if (p == null || p.total == 0) return const SizedBox.shrink();
    final t = context.tokens;
    final text = p.finished
        ? (p.failed == 0
            ? 'Photos encrypted (${p.done})'
            : '${p.failed} photo${p.failed == 1 ? '' : 's'} couldn\'t be encrypted yet; trying again next time')
        : 'Encrypting photos… ${p.done} of ${p.total}';
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(color: t.onMainMuted, fontSize: 12.5)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: p.total == 0 ? null : p.done / p.total, minHeight: 4),
          ],
        ),
      ),
    );
  }
}
