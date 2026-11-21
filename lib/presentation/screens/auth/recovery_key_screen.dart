import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_widgets.dart';

/// Shows a recovery key once. The user must confirm they saved it.
class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen({super.key, required this.recoveryKey, required this.onDone});

  final String recoveryKey;
  final VoidCallback onDone;

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AuthLayout(
        icon: Icons.key_rounded,
        title: 'Save your recovery key',
        message: 'If you forget your password, this key is the only way back in. '
            'Write it down and keep it somewhere safe, away from your phone. It won\'t be shown again.',
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              widget.recoveryKey,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copied. Paste it somewhere safe, then clear your clipboard.'),
              ));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _saved,
            onChanged: (v) => setState(() => _saved = v ?? false),
            title: const Text('I saved my recovery key'),
            subtitle: const Text('Without the password or this key, your data can\'t be recovered by anyone.'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saved ? widget.onDone : null, child: const Text('Continue')),
        ],
      ),
    );
  }
}
