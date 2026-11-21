import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/core_providers.dart';
import '../../widgets/pin_pad.dart';

/// Enter a new 4-6 digit PIN twice. Pops `true` when saved.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _first = '';
  String _pin = '';
  bool _confirming = false;
  String? _error;

  void _digit(String d) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  Future<void> _next() async {
    if (_pin.length < 4) {
      setState(() => _error = 'Use 4 to 6 digits');
      return;
    }
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _pin = '';
        _first = '';
        _confirming = false;
        _error = 'PINs didn\'t match. Try again.';
      });
      return;
    }
    await ref.read(appLockServiceProvider).setPin(_pin);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set PIN')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(_confirming ? 'Enter it again' : 'Choose a 4–6 digit PIN', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'If you forget it, you\'ll need to reinstall the app (which deletes your data). Keep a backup.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            PinDots(length: _pin.length),
            SizedBox(
              height: 32,
              child: Center(child: Text(_error ?? '', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600))),
            ),
            const Spacer(),
            PinPad(
              onDigit: _digit,
              onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: FilledButton(onPressed: _next, child: Text(_confirming ? 'Save PIN' : 'Next')),
            ),
          ],
        ),
      ),
    );
  }
}
