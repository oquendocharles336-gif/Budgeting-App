import 'package:flutter/material.dart';

/// Centered, scrollable column used by the sign-up / login screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.icon, required this.title, this.message, required this.children});

  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                      child: Icon(icon, size: 36, color: scheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(message!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                  ],
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Password input with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
    this.autofocus = false,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    this.autofillHints = const [AutofillHints.password],
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final Iterable<String> autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _obscure,
        autofocus: widget.autofocus,
        enableSuggestions: false,
        autocorrect: false,
        autofillHints: widget.autofillHints,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmitted,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );
}

class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(label),
      );
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});
  final String? text;

  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            text!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
          ),
        );
}
