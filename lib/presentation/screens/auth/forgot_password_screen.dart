import 'package:material_ui/material_ui.dart';

import '../../../domain/security/password_crypto.dart';
import '../../../domain/security/vault.dart';
import 'auth_widgets.dart';

/// Sets a new password using the recovery key.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.onReset, required this.onBack, this.reason});

  /// Why this screen was opened, when it wasn't the user's choice.
  final String? reason;

  /// Throws [WrongSecretException] for a wrong recovery key.
  final Future<void> Function(String recoveryKey, String newPassword) onReset;
  final VoidCallback onBack;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
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
      await widget.onReset(_key.text, _password.text);
      return;
    } on WrongSecretException catch (e) {
      _error = e.message;
    } catch (e) {
      debugPrint('Password reset failed: $e');
      _error = 'Could not reset: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) widget.onBack();
      },
      child: AuthLayout(
        icon: Icons.key_rounded,
        title: 'Reset with recovery key',
        message: widget.reason ??
            'Enter the recovery key you saved when you set up Pitaka, then choose a new in-app PIN or password.',
        children: [
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _key,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Recovery key', hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX'),
                  validator: (v) =>
                      Vault.normalizeRecoveryKey(v ?? '').length != 24 ? 'A recovery key has 24 letters and numbers' : null,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  label: 'New PIN or password',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) => Vault.validatePassword(v ?? ''),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirm,
                  label: 'Enter it again',
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => v != _password.text ? 'They don\'t match' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          BusyButton(label: 'Set new PIN or password', busy: _busy, onPressed: _submit),
          ErrorText(_error),
          const SizedBox(height: 12),
          TextButton(onPressed: _busy ? null : widget.onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}
