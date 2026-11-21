import 'package:flutter/material.dart';

import '../../../domain/services/app_lock_service.dart';
import '../../widgets/motion/animated_icons.dart';
import 'auth_widgets.dart';

/// Lock screen for the "phone screen lock" method: asks the phone (PIN /
/// pattern / password / fingerprint / face) as soon as it's shown.
class DeviceLockScreen extends StatefulWidget {
  const DeviceLockScreen({
    super.key,
    required this.onUnlock,
    required this.onDeviceLockMissing,
    required this.onRecovery,
  });

  /// Shows the phone prompt and, if it succeeds, opens the data.
  final Future<DeviceAuthOutcome> Function() onUnlock;

  /// The phone says it has no screen lock any more.
  final VoidCallback onDeviceLockMissing;

  /// Forgot / can't use the phone lock: use the recovery key.
  final VoidCallback onRecovery;

  @override
  State<DeviceLockScreen> createState() => _DeviceLockScreenState();
}

class _DeviceLockScreenState extends State<DeviceLockScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    DeviceAuthOutcome outcome;
    try {
      outcome = await widget.onUnlock();
    } catch (e) {
      debugPrint('Unlock failed: $e');
      outcome = DeviceAuthOutcome(DeviceAuthStatus.failed, 'Could not open your data: $e');
    }
    if (!mounted) return;
    if (outcome.ok) return; // The app replaces this screen.
    if (outcome.deviceLockMissing) {
      widget.onDeviceLockMissing();
      return;
    }
    setState(() {
      _busy = false;
      _error = outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
        icon: Icons.lock_rounded,
        showLogo: true,
        title: 'Pitaka is locked',
        message: 'Unlock with your phone\'s screen lock: PIN, pattern, password, fingerprint or face.',
        children: [
          // The shackle springs open while the phone checks it's you, and
          // closes again if it wasn't.
          Center(
            child: AnimatedLockIcon(unlocked: _busy, size: 36, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 16),
          BusyButton(label: 'Unlock', busy: _busy, onPressed: _unlock),
          ErrorText(_error),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy ? null : widget.onRecovery,
            child: const Text('Can\'t unlock? Use your recovery key'),
          ),
        ],
      );
}
