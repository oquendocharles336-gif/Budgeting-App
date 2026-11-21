import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/providers/app_state_providers.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/screens/legal/legal_gate_screen.dart';
import 'presentation/screens/lock/lock_screen.dart';
import 'presentation/theme/app_theme.dart';

class PitakaApp extends ConsumerStatefulWidget {
  const PitakaApp({super.key});

  @override
  ConsumerState<PitakaApp> createState() => _PitakaAppState();
}

class _PitakaAppState extends ConsumerState<PitakaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock after the app was in the background for a while. The short
    // grace period stops the lock from appearing after picking a file.
    final lock = ref.read(lockControllerProvider.notifier);
    if (state == AppLifecycleState.paused) {
      lock.markBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      lock.lockIfAwayTooLong();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeControllerProvider);
    final accepted = ref.watch(termsAcceptedProvider);
    final lock = ref.watch(lockControllerProvider);

    return MaterialApp(
      title: 'Pitaka',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(theme.accent),
      darkTheme: AppTheme.dark(theme.accent),
      themeMode: theme.mode,
      // Respect the user's font size, but cap extreme values so layouts hold.
      // The lock screen sits above the navigator, so it also covers any
      // screen that was open when the app went to the background.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.6)),
          child: Stack(
            children: [
              child!,
              if (accepted && lock.locked)
                // Own Overlay so tooltips work above the app's navigator.
                Positioned.fill(
                  child: Overlay(initialEntries: [OverlayEntry(builder: (_) => const LockScreen())]),
                ),
            ],
          ),
        );
      },
      home: accepted ? const HomeShell() : const LegalGateScreen(),
    );
  }
}
