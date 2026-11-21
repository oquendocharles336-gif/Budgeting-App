import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/payment_card.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/sources/sms_parser_source.dart';
import '../../../domain/import/transaction_import_service.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../settings/sms_patterns_screen.dart';
import 'import_review.dart';

/// Android only: read bank SMS alerts on the device, review, then save.
class SmsImportScreen extends ConsumerStatefulWidget {
  const SmsImportScreen({super.key, required this.card});
  final PaymentCard card;

  @override
  ConsumerState<SmsImportScreen> createState() => _SmsImportScreenState();
}

class _SmsImportScreenState extends ConsumerState<SmsImportScreen> {
  bool? _hasPermission;
  bool _includeWithoutCard = false;
  int _days = 30;
  bool _busy = false;
  List<ImportCandidate>? _candidates;

  @override
  void initState() {
    super.initState();
    _includeWithoutCard = widget.card.type == CardType.ewallet;
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final inbox = ref.read(smsInboxProvider);
    final ok = inbox.isSupported && await inbox.hasPermission();
    if (mounted) setState(() => _hasPermission = ok);
  }

  Future<void> _requestPermission() async {
    final granted = await ref.read(smsInboxProvider).requestPermission();
    if (granted) await ref.read(settingsRepositoryProvider).set(SettingsRepository.smsEnabled, '1');
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    if (!granted) {
      showSnack(context, 'Permission not given. You can allow it later in your phone\'s settings.');
    }
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      final patterns = await ref.read(smsPatternRepositoryProvider).all();
      final source = SmsParserSource(
        inbox: ref.read(smsInboxProvider),
        patterns: patterns,
        includeWithoutCardNumber: _includeWithoutCard,
        lookback: Duration(days: _days),
      );
      final candidates = await ref.read(importServiceProvider).preview(source, card: widget.card);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final candidates = _candidates;
    return PopScope(
      canPop: candidates == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _candidates = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('SMS import · ${widget.card.nickname}'),
          actions: [
            IconButton(
              tooltip: 'SMS patterns',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmsPatternsScreen())),
            ),
          ],
        ),
        body: candidates != null
            ? ImportReview(candidates: candidates, onSaved: () => Navigator.of(context).pop())
            : _hasPermission == null
                ? const LoadingView()
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Icon(Icons.sms_rounded, size: 52, color: scheme.primary),
                      const SizedBox(height: 12),
                      Text('Read bank SMS alerts', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        'Pitaka looks through your text messages on this phone for purchase alerts that mention the card '
                        '${widget.card.hasMobileNumber ? widget.card.maskedNumber : 'ending in ${widget.card.last4}'}. Messages never leave your phone, one-time PINs are skipped, '
                        'and nothing is saved until you review it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      if (!_hasPermission!) ...[
                        FilledButton.icon(
                          onPressed: _requestPermission,
                          icon: const Icon(Icons.lock_open_rounded),
                          label: const Text('Allow SMS access'),
                        ),
                      ] else ...[
                        DropdownButtonFormField<int>(
                          initialValue: _days,
                          decoration: const InputDecoration(labelText: 'Look back'),
                          items: const [
                            DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                            DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                            DropdownMenuItem(value: 60, child: Text('Last 60 days')),
                            DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                          ],
                          onChanged: (v) => setState(() => _days = v ?? 30),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Include alerts without a card number'),
                          subtitle: const Text('Useful for e-wallets like GCash or Maya.'),
                          value: _includeWithoutCard,
                          onChanged: (v) => setState(() => _includeWithoutCard = v),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _scan,
                          icon: const Icon(Icons.search_rounded),
                          label: Text(_busy ? 'Reading messages…' : 'Find transactions'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Not finding your bank\'s texts? Adjust the patterns with the ⚙ button above.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }
}
