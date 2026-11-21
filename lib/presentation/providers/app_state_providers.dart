import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/repositories/settings_repository.dart';
import '../theme/app_palette.dart';
import 'core_providers.dart';

/// Bump this when the privacy policy or terms change in a way users must
/// accept again.
const currentTermsVersion = '5'; // 2: password + encryption; 3: Pay Later, business side, photos; 4: encrypted photos in backups; 5: optional update check (internet)

// -----------------------------------------------------------------------------
// Theme
// -----------------------------------------------------------------------------

class ThemeSettings {
  const ThemeSettings({required this.mode, required this.accent});
  final ThemeMode mode;
  final Color accent;

  /// Midnight: midnight navy / graphite / sunset orange.
  static const defaultAccent = AppPalettes.sunsetOrange;

  ThemeSettings copyWith({ThemeMode? mode, Color? accent}) =>
      ThemeSettings(mode: mode ?? this.mode, accent: accent ?? this.accent);
}

class ThemeController extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() => _fromSettings(ref.read(initialSettingsProvider));

  /// Re-applies saved settings (after restoring a backup).
  void reloadFrom(Map<String, String> settings) => state = _fromSettings(settings);

  static ThemeSettings _fromSettings(Map<String, String> s) {
    final mode = switch (s[SettingsRepository.themeMode]) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final accentValue = int.tryParse(s[SettingsRepository.accentColor] ?? '');
    return ThemeSettings(
      mode: mode,
      accent: accentValue == null ? ThemeSettings.defaultAccent : Color(accentValue),
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await ref.read(settingsRepositoryProvider).set(SettingsRepository.themeMode, mode.name);
  }

  Future<void> setAccent(Color color) async {
    state = state.copyWith(accent: color);
    await ref.read(settingsRepositoryProvider).set(SettingsRepository.accentColor, '${color.toARGB32()}');
  }
}

final themeControllerProvider = NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);

// -----------------------------------------------------------------------------
// Currency
// -----------------------------------------------------------------------------

class CurrencyController extends Notifier<CurrencyInfo> {
  @override
  CurrencyInfo build() => CurrencyInfo.byCode(ref.read(initialSettingsProvider)[SettingsRepository.currency]);

  void reloadFrom(Map<String, String> settings) =>
      state = CurrencyInfo.byCode(settings[SettingsRepository.currency]);

  Future<void> set(CurrencyInfo c) async {
    state = c;
    await ref.read(settingsRepositoryProvider).set(SettingsRepository.currency, c.code);
  }
}

final currencyProvider = NotifierProvider<CurrencyController, CurrencyInfo>(CurrencyController.new);

// -----------------------------------------------------------------------------
// Terms acceptance (first launch)
// -----------------------------------------------------------------------------

class TermsController extends Notifier<bool> {
  @override
  bool build() => ref.read(initialSettingsProvider)[SettingsRepository.termsAccepted] == currentTermsVersion;

  Future<void> accept() async {
    await ref.read(settingsRepositoryProvider).set(SettingsRepository.termsAccepted, currentTermsVersion);
    state = true;
  }
}

final termsAcceptedProvider = NotifierProvider<TermsController, bool>(TermsController.new);