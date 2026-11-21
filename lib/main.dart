import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'domain/services/notification_service.dart';
import 'presentation/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const _Bootstrap());
}

/// Opens the database before showing the app, with a friendly error screen
/// if that fails (e.g. a corrupted file).
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<_Ready> _ready = _init();

  Future<_Ready> _init() async {
    final db = await AppDatabase.open();
    final settings = await SettingsRepository(db.db).all();
    final notifications = NotificationService();
    await notifications.init();
    return _Ready(db, settings, notifications);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Ready>(
      future: _ready,
      builder: (context, snap) {
        if (snap.hasData) {
          final r = snap.data!;
          return ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(r.db),
              initialSettingsProvider.overrideWithValue(r.settings),
              notificationServiceProvider.overrideWithValue(r.notifications),
            ],
            child: const PitakaApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: snap.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storage_rounded, size: 48),
                          const SizedBox(height: 12),
                          const Text('Could not open your data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text('${snap.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => setState(() => _ready = _init()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}

class _Ready {
  _Ready(this.db, this.settings, this.notifications);
  final AppDatabase db;
  final Map<String, String> settings;
  final NotificationService notifications;
}
