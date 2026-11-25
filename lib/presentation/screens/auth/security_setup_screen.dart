import 'package:material_ui/material_ui.dart';

import 'auth_widgets.dart';

/// First launch: choose how the app is unlocked.
///
///  * Phone screen lock (only offered when the phone has one): the phone's
///    own PIN / pattern / password, plus fingerprint or face if set up.
///  * In-app PIN or password: for phones without a screen lock, or if the
///    user prefers a separate code for this app.
class SecuritySetupScreen extends StatefulWidget {
  const SecuritySetupScreen({
    super.key,
    required this.deviceSupported,
    required this.hasExistingData,
    required this.onUseDevice,
    required this.onUsePin,
  });

  /// `local_auth` isDeviceSupported(): the phone has a screen lock.
  final bool deviceSupported;
  final bool hasExistingData;

  /// Asks the phone to confirm, then sets everything up. Throws an
  /// exception whose text can be shown when it doesn't work.
  final Future<void> Function() onUseDevice;
  final VoidCallback onUsePin;

  @override
  State<SecuritySetupScreen> createState() => _SecuritySetupScreenState();
}

class _SecuritySetupScreenState extends State<SecuritySetupScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _useDevice() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onUseDevice();
      return; // The app moves on to the recovery key.
    } catch (e) {
      debugPrint('Device lock set-up failed: $e');
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AuthLayout(
      icon: Icons.shield_rounded,
      showLogo: true,
      title: 'Secure Pitaka',
      message: widget.hasExistingData
          ? 'Pitaka now encrypts your data. Choose how you\'ll unlock it.'
          : 'Your money data is encrypted on this phone. Choose how you\'ll unlock it.',
      children: [
        if (widget.deviceSupported)
          _MethodCard(
            icon: Icons.fingerprint_rounded,
            title: 'Use phone screen lock',
            subtitle: 'Your phone PIN, pattern or password, plus fingerprint or face if you\'ve set them up.',
            recommended: true,
            busy: _busy,
            onTap: _busy ? null : _useDevice,
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This phone has no screen lock, so set a PIN or password for Pitaka. '
                    'You can switch to the phone lock later in Settings.',
                    style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.dialpad_rounded,
          title: 'Set an in-app PIN or password',
          subtitle: 'A separate code just for this app.',
          recommended: !widget.deviceSupported,
          onTap: _busy ? null : widget.onUsePin,
        ),
        ErrorText(_error),
        const SizedBox(height: 16),
        Text(
          'Either way, you\'ll get a recovery key next in case you can\'t unlock.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.recommended = false,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool recommended;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: recommended ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: recommended ? scheme.onPrimaryContainer : scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: recommended ? scheme.onPrimaryContainer : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        height: 1.3,
                        color: recommended ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              else
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
