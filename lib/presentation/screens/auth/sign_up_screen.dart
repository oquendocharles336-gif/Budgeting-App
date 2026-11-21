import 'package:flutter/material.dart';

import '../../../domain/security/vault.dart';
import 'auth_widgets.dart';

/// First launch: create the password that encrypts everything.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.hasExistingData, required this.onCreate});

  /// True when an older, unencrypted database is on the phone.
  final bool hasExistingData;

  /// Sets up the encrypted database. Throws on failure.
  final Future<void> Function(String password) onCreate;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCreate(_password.text);
    } catch (e) {
      debugPrint('Account set-up failed: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not set up encryption: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AuthLayout(
      icon: Icons.lock_person_rounded,
      title: 'Create your password',
      message: widget.hasExistingData
          ? 'Pitaka now encrypts your data. Set a password and your existing cards, transactions and debts '
              'will be encrypted with it.'
          : 'Everything you add is encrypted on this phone with this password.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PasswordField(
                  controller: _password,
                  autofocus: true,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) => Vault.validatePassword(v ?? ''),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirm,
                  label: 'Confirm password',
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => v != _password.text ? 'Passwords don\'t match' : null,
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
            'Only you can unlock it. The password never leaves this phone and is never stored, so nobody, '
            'not even the app\'s developer, can see your data or reset your password. '
            'You\'ll get a recovery key next in case you forget it.',
            style: TextStyle(color: scheme.onSecondaryContainer, height: 1.4),
          ),
        ),
        const SizedBox(height: 24),
        BusyButton(label: widget.hasExistingData ? 'Encrypt my data' : 'Create password', busy: _busy, onPressed: _submit),
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
      ],
    );
  }
}
