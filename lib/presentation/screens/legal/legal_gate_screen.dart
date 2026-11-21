import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/legal_text.dart';
import '../../providers/app_state_providers.dart';
import '../../theme/app_theme.dart';
import 'legal_document_screen.dart';

/// First-launch screen: what the app is, the privacy promise, and an
/// "I agree" checkbox that must be ticked to continue.
class LegalGateScreen extends ConsumerStatefulWidget {
  const LegalGateScreen({super.key});

  @override
  ConsumerState<LegalGateScreen> createState() => _LegalGateScreenState();
}

class _LegalGateScreenState extends ConsumerState<LegalGateScreen> {
  bool _agreed = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppTheme.heroGradient(scheme),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(Icons.account_balance_wallet_rounded, size: 38, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 24),
                  Text('Welcome to Pitaka', style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Track spending, budgets and debts. Works fully offline. No sign-up.',
                    style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  Text('Your privacy', style: text.titleMedium),
                  const SizedBox(height: 12),
                  for (final line in LegalText.privacySummary)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_rounded, size: 20, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(child: Text(line, style: text.bodyMedium)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: () => _open(context, 'Privacy Policy', LegalText.privacyPolicy),
                        icon: const Icon(Icons.privacy_tip_outlined),
                        label: const Text('Privacy Policy'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: () => _open(context, 'Terms & Conditions', LegalText.terms),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Terms & Conditions'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('I have read and agree to the Privacy Policy and Terms & Conditions'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: !_agreed || _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            await ref.read(termsAcceptedProvider.notifier).accept();
                          },
                    child: const Text('Get started'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, String title, String body) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LegalDocumentScreen(title: title, body: body)));
  }
}
