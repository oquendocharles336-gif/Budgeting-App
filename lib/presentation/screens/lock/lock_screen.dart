import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/pin_pad.dart';

/// Covers the whole app until the PIN (or biometrics) is entered.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _error;
  bool _biometricAvailable = false;
  int _failures = 0;
  DateTime? _blockedUntil;

  @override
  void initState() {
    super.initState();
    _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    final lock = ref.read(appLockServiceProvider);
    final enabled = await lock.isBiometricEnabled() && await lock.canUseBiometrics();
    if (!mounted) return;
    setState(() => _biometricAvailable = enabled);
    if (enabled) {
      final ok = await lock.authenticateWithBiometrics();
      if (ok && mounted) ref.read(lockControllerProvider.notifier).unlock();
    }
  }

  Future<void> _onDigit(String d) async {
    if (_blockedUntil != null && DateTime.now().isBefore(_blockedUntil!)) return;
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length >= 4) {
      final ok = await ref.read(appLockServiceProvider).verifyPin(_pin);
      if (!mounted) return;
      if (ok) {
        ref.read(lockControllerProvider.notifier).unlock();
      } else if (_pin.length == 6) {
        _wrong();
      }
    }
  }

  void _wrong() {
    HapticFeedback.heavyImpact();
    _failures++;
    setState(() {
      _pin = '';
      if (_failures >= 5) {
        _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _failures = 0;
        _error = 'Too many tries. Wait 30 seconds.';
      } else {
        _error = 'Wrong PIN';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.lock_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Enter your PIN', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            PinDots(length: _pin.length),
            SizedBox(
              height: 32,
              child: Center(
                child: Text(_error ?? '', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
              ),
            ),
            // Auto-unlocks as soon as the right PIN is typed. For a shorter
            // PIN typed wrong, "Unlock" confirms the attempt.
            SizedBox(
              height: 48,
              child: _pin.length >= 4 && _pin.length < 6
                  ? TextButton(onPressed: _wrong, child: const Text('Unlock'))
                  : null,
            ),
            const Spacer(),
            PinPad(
              onDigit: _onDigit,
              onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
              extraButton: _biometricAvailable
                  ? IconButton(
                      iconSize: 32,
                      tooltip: 'Use fingerprint or face',
                      onPressed: _tryBiometric,
                      icon: const Icon(Icons.fingerprint_rounded),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
