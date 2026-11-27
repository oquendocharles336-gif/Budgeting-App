import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/business.dart';
import '../../../domain/services/photo_service.dart';
import '../../providers/business_providers.dart';
import '../../providers/core_providers.dart';
import '../../theme/app_palette.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_widgets.dart';

/// The QR payment methods (Maya, MariBank, BDO).
List<PaymentMethod> get qrPaymentMethods => [for (final m in PaymentMethod.values) if (m.usesQr) m];

/// Picks the owner's QR image for [method] from the gallery and saves it
/// (encrypted, on this phone only). Shows a message for the result.
Future<void> setUpPaymentQr(BuildContext context, WidgetRef ref, PaymentMethod method) async {
  try {
    final path = await ref.read(photoServiceProvider).setPaymentQr(method.dbValue);
    if (path == null) return; // cancelled
    ref.refreshData();
    if (context.mounted) showSnack(context, '${method.shortLabel} QR saved');
  } on PhotoAccessDenied catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not save the QR: $e', error: true);
  }
}

Future<void> removePaymentQr(BuildContext context, WidgetRef ref, PaymentMethod method) async {
  final ok = await confirm(
    context,
    title: 'Remove ${method.shortLabel} QR?',
    message: 'Buyers won\'t see a QR for ${method.shortLabel} until you upload one again.',
    confirmLabel: 'Remove',
  );
  if (!ok) return;
  try {
    await ref.read(photoServiceProvider).removePaymentQr(method.dbValue);
    ref.refreshData();
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not remove the QR: $e', error: true);
  }
}

/// The QR the buyer scans at checkout. With no QR uploaded yet it shows a
/// "Set up QR" button right here, so the owner can add it mid-sale.
class PaymentQrCard extends ConsumerWidget {
  const PaymentQrCard({super.key, required this.method, this.size = 220});
  final PaymentMethod method;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final path = ref.watch(paymentQrPathProvider(method)).asDataOrNull;
    final name = method.shortLabel;
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  path == null ? 'Your $name QR' : 'Let the buyer scan to pay with $name',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (path != null)
                IconButton(
                  tooltip: 'Change $name QR',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => setUpPaymentQr(context, ref, method),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (path == null)
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: t.secondHigh, borderRadius: BorderRadius.circular(12)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 56, color: t.onSecondMuted),
                  const SizedBox(height: 8),
                  Text(
                    'No $name QR yet. Upload a screenshot of your QR from the $name app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.onSecond),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => setUpPaymentQr(context, ref, method),
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Set up QR'),
                  ),
                ],
              ),
            )
          else
            _QrImage(path: path, size: size, label: '$name payment QR code'),
          const SizedBox(height: 8),
          Text(
            'Check the payment in your $name app before saving.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.onSecondMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The decrypted QR, shown at full quality (not cropped) so it scans.
class _QrImage extends ConsumerWidget {
  const _QrImage({required this.path, required this.size, required this.label});
  final String path;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final bytes = ref.watch(photoBytesProvider(path));
    Widget box(Widget child) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: child,
        );
    return bytes.when(
      loading: () => box(const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
      error: (_, _) => box(Text('QR could not be opened', style: TextStyle(color: t.onSecond))),
      data: (data) => data == null
          ? box(Text('QR could not be opened. Upload it again.', textAlign: TextAlign.center, style: TextStyle(color: t.onSecond)))
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(data, width: size, height: size, fit: BoxFit.contain, semanticLabel: label, gaplessPlayback: true),
            ),
    );
  }
}

/// Business > Payment QR codes (also in Settings when Business Mode is
/// on): one slot each for Maya, MariBank and BDO.
class PaymentQrScreen extends ConsumerWidget {
  const PaymentQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment QR codes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Upload your own QR from each app (a screenshot works). Buyers see it when you choose that payment '
            'method on an order. QR images stay on this phone, encrypted, and aren\'t included in backups.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          for (final m in qrPaymentMethods) _QrSlot(method: m),
        ],
      ),
    );
  }
}

class _QrSlot extends ConsumerWidget {
  const _QrSlot({required this.method});
  final PaymentMethod method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(paymentQrPathProvider(method)).asDataOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: path == null
              ? const Icon(Icons.qr_code_2_rounded, size: 40)
              : PhotoThumb(path: path, label: '${method.shortLabel} QR', fallbackIcon: Icons.qr_code_2_rounded),
          title: Text(method.label),
          subtitle: Text(path == null ? 'Not set up' : 'Shown to buyers at checkout'),
          trailing: Wrap(
            spacing: 4,
            children: [
              if (path != null)
                IconButton(
                  tooltip: 'Remove ${method.shortLabel} QR',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => removePaymentQr(context, ref, method),
                ),
              FilledButton.tonal(
                onPressed: () => setUpPaymentQr(context, ref, method),
                child: Text(path == null ? 'Upload QR image' : 'Change'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
