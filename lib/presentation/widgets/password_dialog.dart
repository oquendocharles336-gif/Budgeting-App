import 'package:material_ui/material_ui.dart';

/// Asks for a password. [check] runs with a spinner and returns an error
/// message to show, or null to accept. Returns the password, or null if
/// cancelled.
Future<String?> askPassword(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Password',
  String confirmLabel = 'Continue',
  required Future<String?> Function(String password) check,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordDialog(
        title: title,
        message: message,
        label: label,
        confirmLabel: confirmLabel,
        check: check,
      ),
    );

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.confirmLabel,
    required this.check,
  });

  final String title;
  final String? message;
  final String label;
  final String confirmLabel;
  final Future<String?> Function(String password) check;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _controller.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.check(_controller.text);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(_controller.text);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 16)],
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !_busy,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: _error,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(widget.confirmLabel),
          ),
        ],
      );
}
