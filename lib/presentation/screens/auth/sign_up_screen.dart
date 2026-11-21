import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/security/vault.dart';
import 'auth_widgets.dart';

/// Creates the in-app PIN or password (typed twice) that unlocks the
/// encrypted data. Used on first launch, when the phone's screen lock was
/// removed, and when switching method in Settings.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    super.key,
    required this.hasExistingData,
    required this.onCreate,
    this.onBack,
    this.title = 'Create your PIN or password',
    this.message,
    this.buttonLabel,
    this.showRecoveryNote = true,
    this.backLabel = 'Choose another way to unlock',
  });

  /// True when an older, unencrypted database is on the phone.
  final bool hasExistingData;

  /// Saves the new secret. Throws on failure.
  final Future<void> Function(String password) onCreate;

  /// Back to the unlock-method choice, or cancel (null hides the button).
  final VoidCallback? onBack;
  final String backLabel;
  final String title;
  final String? message;
  final String? buttonLabel;

  /// "You'll get a recovery key next" (first set-up only).
  final bool showRecoveryNote;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _numeric = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCreate(_password.text);
    } catch (e) {
      debugPrint('PIN set-up failed: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not set up encryption: $e';
        });
      }
    }
  }

  String? _validate(String? v) {
    final text = v ?? '';
    if (text.isEmpty) return _numeric ? 'Enter a PIN' : 'Enter a password';
    if (_numeric && !RegExp(r'^\d+$').hasMatch(text)) return 'A PIN can only have numbers';
    return Vault.validatePassword(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final noun = _numeric ? 'PIN' : 'password';
    final keyboard = _numeric ? TextInputType.number : TextInputType.visiblePassword;
    final formatters = _numeric ? [FilteringTextInputFormatter.digitsOnly] : const <TextInputFormatter>[];
    return AuthLayout(
      icon: Icons.lock_person_rounded,
      showLogo: true,
      title: widget.title,
      message: widget.message ??
          (widget.hasExistingData
              ? 'Pitaka now encrypts your data. Set a PIN or password and your existing cards, transactions and '
                  'debts will be encrypted with it.'
              : 'Everything you add is encrypted on this phone with this PIN or password.'),
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('PIN'), icon: Icon(Icons.dialpad_rounded)),
            ButtonSegment(value: false, label: Text('Password'), icon: Icon(Icons.password_rounded)),
          ],
          selected: {_numeric},
          onSelectionChanged: _busy
              ? null
              : (s) => setState(() {
                    _numeric = s.first;
                    _password.clear();
                    _confirm.clear();
                    _error = null;
                  }),
        ),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PasswordField(
                  key: ValueKey('pw-$_numeric'),
                  inputFormatters: formatters,
                  controller: _password,
                  label: _numeric ? 'PIN (${Vault.minPinLength}-${Vault.maxPinLength} digits)' : 'Password',
                  keyboardType: keyboard,
                  autofocus: true,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: _validate,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  key: ValueKey('confirm-$_numeric'),
                  inputFormatters: formatters,
                  controller: _confirm,
                  label: 'Enter the $noun again',
                  keyboardType: keyboard,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => v != _password.text ? 'The ${noun}s don\'t match' : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Text(
            'Only you can unlock it. The $noun never leaves this phone and is never stored (a salted, slow '
            'PBKDF2-SHA256 hash of it locks the key), so nobody, not even the app\'s developer, can see your '
            'data or reset it.${widget.showRecoveryNote ? ' You\'ll get a recovery key next in case you forget it.' : ''}',
            style: TextStyle(color: scheme.onSecondaryContainer, height: 1.4),
          ),
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: widget.buttonLabel ?? (widget.hasExistingData ? 'Encrypt my data' : 'Create $noun'),
          busy: _busy,
          onPressed: _submit,
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Securing your data. This can take a few seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ErrorText(_error),
        if (widget.onBack != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: _busy ? null : widget.onBack, child: Text(widget.backLabel)),
        ],
      ],
    );
  }
}
