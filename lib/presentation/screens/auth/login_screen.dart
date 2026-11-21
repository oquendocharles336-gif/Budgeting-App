import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/security/password_crypto.dart';
import 'auth_widgets.dart';

/// Unlocks the encrypted database with the password (or fingerprint).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onPassword,
    required this.onForgot,
    this.onBiometric,
  });

  /// Throws [WrongSecretException] for a wrong password.
  final Future<void> Function(String password) onPassword;
  final VoidCallback onForgot;

  /// Null when fingerprint unlock is off. Returns false if cancelled.
  final Future<bool> Function()? onBiometric;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  int _failures = 0;
  DateTime? _waitUntil;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.onBiometric != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _password.dispose();
    super.dispose();
  }

  int get _secondsLeft {
    final until = _waitUntil;
    if (until == null) return 0;
    final s = until.difference(DateTime.now()).inSeconds;
    return s > 0 ? s + 1 : 0;
  }

  Future<void> _biometric() async {
    final f = widget.onBiometric;
    if (f == null || _busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      debugPrint('Biometric unlock failed: $e');
      if (mounted) setState(() => _error = 'Fingerprint unlock failed. Use your password.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() async {
    if (_busy || _secondsLeft > 0 || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPassword(_password.text);
      return; // The app replaces this screen.
    } on WrongSecretException {
      HapticFeedback.heavyImpact();
      _failures++;
      _password.clear();
      _error = 'Wrong password';
      // Slow down guessing on this screen. (The real protection is the
      // key stretching: each guess is expensive even with the file copied.)
      if (_failures >= 5) {
        final seconds = 30 * (1 << math.min(_failures - 5, 5));
        _waitUntil = DateTime.now().add(Duration(seconds: seconds));
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || _secondsLeft == 0) t.cancel();
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      debugPrint('Unlock failed: $e');
      _error = 'Could not open your data: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final wait = _secondsLeft;
    return AuthLayout(
      icon: Icons.lock_rounded,
      title: 'Welcome back',
      message: 'Enter your password to unlock your data.',
      children: [
        AutofillGroup(
          child: PasswordField(
            controller: _password,
            autofocus: widget.onBiometric == null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: 20),
        BusyButton(label: wait > 0 ? 'Try again in ${wait}s' : 'Unlock', busy: _busy || wait > 0, onPressed: _submit),
        if (widget.onBiometric != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _biometric,
            icon: const Icon(Icons.fingerprint_rounded),
            label: const Text('Use fingerprint or face'),
          ),
        ],
        ErrorText(_error),
        const SizedBox(height: 12),
        TextButton(onPressed: _busy ? null : widget.onForgot, child: const Text('Forgot password?')),
      ],
    );
  }
}
