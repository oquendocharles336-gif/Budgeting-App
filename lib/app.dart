import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'data/repositories/op_guard.dart';
import 'domain/services/app_lock_service.dart';
import 'presentation/providers/app_state_providers.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/providers/photo_migration_provider.dart';
import 'presentation/screens/auth/auth_widgets.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/screens/legal/legal_gate_screen.dart';
import 'presentation/theme/app_theme.dart';

class PitakaApp extends ConsumerStatefulWidget {
  const PitakaApp({super.key});

  @override
  ConsumerState<PitakaApp> createState() => _PitakaAppState();
}

class _PitakaAppState extends ConsumerState<PitakaApp> with WidgetsBindingObserver {
  /// When leaving the app on purpose (file picker, the phone's unlock
  /// screen), it stays unlocked, but not for longer than this.
  static const guardedLockAfter = Duration(minutes: 2);
  DateTime? _backgroundedAt;

  /// Covers the screen while the app isn't in front, so balances don't show
  /// in the app switcher or for a frame when coming back.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Debt reminders are re-created each time the data is unlocked, so they
    // survive app updates and anything the OS dropped (the plugin's boot
    // receiver already restores them after a reboot).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await ref.read(debtServiceProvider).rescheduleAll(currencySymbol: ref.read(currencyProvider).symbol);
      } catch (e) {
        debugPrint('Could not restore debt reminders: $e');
      }
      try {
        // Reminders left by a feature removed in this version.
        await ref.read(notificationServiceProvider).cancelRetiredReminders();
      } catch (e) {
        debugPrint('Could not cancel retired reminders: $e');
      }
      try {
        // Retry keys are only needed for minutes; keep the table small.
        await OpGuard.prune(ref.read(databaseProvider).db);
      } catch (e) {
        debugPrint('Could not prune op keys: $e');
      }
      // One-time: encrypt photos saved before photos were encrypted.
      if (mounted) ref.read(photoMigrationProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        if (!_covered) setState(() => _covered = true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_backgroundedAt != null) return;
        if (LockGuard.suspended) {
          _backgroundedAt = DateTime.now();
        } else {
          // Lock as soon as the app goes to the background: the database is
          // closed and the lock screen is what shows when the user returns.
          ref.read(sessionProvider).lock();
        }
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && DateTime.now().difference(since) >= guardedLockAfter) {
          ref.read(sessionProvider).lock();
          return;
        }
        if (_covered) setState(() => _covered = false);
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeControllerProvider);
    final accepted = ref.watch(termsAcceptedProvider);

    return MaterialApp(
      title: 'Pitaka',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(theme.accent),
      darkTheme: AppTheme.dark(theme.accent),
      themeMode: theme.mode,
      // Respect the user's font size, but cap extreme values so layouts hold.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.6)),
          child: Stack(
            children: [
              // fl_chart still imports package:flutter/material.dart; the bridge
              // gives those widgets the app's theme and localizations.
              // TODO: remove the bridge (and this ignore) once fl_chart
              // imports package:material_ui. Still needed as of fl_chart 1.3.1.
              // ignore: deprecated_member_use
              MaterialUiCompatibilityBridge(child: child!),
              if (_covered) const Positioned.fill(child: _PrivacyCover()),
            ],
          ),
        );
      },
      home: accepted ? const HomeShell() : const LegalGateScreen(),
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: const Center(child: AppLogo(size: 96)),
  );
}