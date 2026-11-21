import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/providers/app_state_providers.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/screens/legal/legal_gate_screen.dart';
import 'presentation/theme/app_theme.dart';

class PitakaApp extends ConsumerStatefulWidget {
  const PitakaApp({super.key});

  @override
  ConsumerState<PitakaApp> createState() => _PitakaAppState();
}

class _PitakaAppState extends ConsumerState<PitakaApp> with WidgetsBindingObserver {
  /// Short grace period so picking a file or answering a call doesn't log out.
  static const lockAfter = Duration(seconds: 30);
  DateTime? _backgroundedAt;

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
    // Sign out (close the encrypted database) after the app was in the
    // background for a while.
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && DateTime.now().difference(since) >= lockAfter) {
        ref.read(sessionProvider).lock();
      }
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
          child: child!,
        );
      },
      home: accepted ? const HomeShell() : const LegalGateScreen(),
    );
  }
}
