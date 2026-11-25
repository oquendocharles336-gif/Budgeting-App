import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/security/password_crypto.dart';
import '../../../domain/security/vault.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../auth/auth_widgets.dart';

/// Changes the password. Only the small key file is re-encrypted; the
/// recovery key and fingerprint unlock keep working.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
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
      await ref.read(sessionProvider).vault.changePassword(current: _current.text, next: _next.text);
      if (!mounted) return;
      showSnack(context, 'PIN or password changed');
      Navigator.of(context).pop();
      return;
    } on WrongSecretException {
      _error = 'Current PIN or password is wrong';
    } catch (e) {
      _error = 'Could not change password: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Change PIN or password')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              PasswordField(controller: _current, label: 'Current PIN or password', autofocus: true),
              const SizedBox(height: 16),
              PasswordField(
                controller: _next,
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
                validator: (v) => v != _next.text ? 'They don\'t match' : null,
              ),
              const SizedBox(height: 12),
              Text(
                'Backups you already made still open with the password they were made with.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 24),
              BusyButton(label: 'Change', busy: _busy, onPressed: _submit),
              ErrorText(_error),
            ],
          ),
        ),
      );
}
