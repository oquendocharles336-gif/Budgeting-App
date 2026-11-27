import 'package:flutter/services.dart';
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

/// Payment methods whose QR is being picked or saved right now. Their
/// buttons are disabled meanwhile, so a second tap can't open a second
/// picker (the picker refuses that with "already_active").
class PaymentQrBusy extends Notifier<Set<PaymentMethod>> {
  @override
  Set<PaymentMethod> build() => const {};

  /// False when [m] is already busy.
  bool start(PaymentMethod m) {
    if (state.contains(m)) return false;
    state = {...state, m};
    return true;
  }

  void finish(PaymentMethod m) => state = {...state}..remove(m);
}

final paymentQrBusyProvider = NotifierProvider<PaymentQrBusy, Set<PaymentMethod>>(PaymentQrBusy.new);

/// Reloads the QR for [method] everywhere it is shown. Uses the container,
/// not the widget's ref: the button's widget may have been rebuilt or
/// closed while the gallery was open.
void _refreshQr(ProviderContainer container, PaymentMethod method) {
  try {
    container.invalidate(paymentQrPathProvider(method));
    container.read(dataRevisionProvider.notifier).bump();
  } catch (e) {
    debugPrint('Session closed before the QR screen refreshed: $e');
  }
}

/// Picks the owner's QR image for [method] from the gallery and saves it
/// (encrypted, on this phone only), replacing any QR set before. Shows a
/// message for the result.
Future<void> setUpPaymentQr(BuildContext context, WidgetRef ref, PaymentMethod method) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final busy = container.read(paymentQrBusyProvider.notifier);
  if (!busy.start(method)) return;
  final messenger = ScaffoldMessenger.of(context);
  void tell(String text, {bool error = false}) {
    if (context.mounted) {
      showSnack(context, text, error: error);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  final hadOne = container.read(paymentQrPathProvider(method)).asDataOrNull != null;
  try {
    final path = await container.read(photoServiceProvider).setPaymentQr(method.dbValue);
    if (path == null) return; // cancelled: the current QR stays
    _refreshQr(container, method);
    tell(hadOne ? '${method.shortLabel} QR changed' : '${method.shortLabel} QR saved');
  } on PhotoAccessDenied catch (e) {
    tell(e.message, error: true);
  } on PlatformException catch (e) {
    tell(
      e.code == 'already_active' ? 'The photo picker is already open.' : 'Could not open your photos: ${e.message ?? e.code}',
      error: true,
    );
  } catch (e) {
    tell('Could not save the QR: $e', error: true);
  } finally {
    try {
      busy.finish(method);
    } catch (_) {
      // Locked meanwhile: the whole session state is gone anyway.
    }
  }
}

Future<void> removePaymentQr(BuildContext context, WidgetRef ref, PaymentMethod method) async {
  final ok = await confirm(
    context,
    title: 'Remove ${method.shortLabel} QR?',
    message: 'Buyers won\'t see a QR for ${method.shortLabel} until you upload one again.',
    confirmLabel: 'Remove',
  );
  if (!ok || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final busy = container.read(paymentQrBusyProvider.notifier);
  if (!busy.start(method)) return;
  try {
    await container.read(photoServiceProvider).removePaymentQr(method.dbValue);
    _refreshQr(container, method);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not remove the QR: $e', error: true);
  } finally {
    try {
      busy.finish(method);
    } catch (_) {}
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
    final busy = ref.watch(paymentQrBusyProvider).contains(method);
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
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              else if (path != null) ...[
                IconButton(
                  tooltip: 'Change $name QR',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => setUpPaymentQr(context, ref, method),
                ),
                IconButton(
                  tooltip: 'Remove $name QR',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => removePaymentQr(context, ref, method),
                ),
              ],
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
                    onPressed: busy ? null : () => setUpPaymentQr(context, ref, method),
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Set up QR'),
                  ),
                ],
              ),
            )
          else
            // Keyed by path: a new QR is a new file, so the image is rebuilt
            // from the new bytes instead of reusing the old picture.
            _QrImage(key: ValueKey(path), path: path, size: size, label: '$name payment QR code'),
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
  const _QrImage({super.key, required this.path, required this.size, required this.label});
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
              child: Image.memory(data, width: size, height: size, fit: BoxFit.contain, semanticLabel: label),
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
    final busy = ref.watch(paymentQrBusyProvider).contains(method);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: path == null
              ? const Icon(Icons.qr_code_2_rounded, size: 40)
              : PhotoThumb(
                  key: ValueKey(path),
                  path: path,
                  label: '${method.shortLabel} QR',
                  fallbackIcon: Icons.qr_code_2_rounded,
                ),
          title: Text(method.label),
          subtitle: Text(path == null ? 'Not set up' : 'Shown to buyers at checkout'),
          trailing: Wrap(
            spacing: 4,
            children: [
              if (path != null)
                IconButton(
                  tooltip: 'Remove ${method.shortLabel} QR',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: busy ? null : () => removePaymentQr(context, ref, method),
                ),
              FilledButton.tonal(
                onPressed: busy ? null : () => setUpPaymentQr(context, ref, method),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                    : Text(path == null ? 'Upload QR image' : 'Change'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
