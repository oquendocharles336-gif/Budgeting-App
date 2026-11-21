/// Compile-time feature flags.
///
/// Turn bank sync on for a dev build with:
///   flutter run --dart-define=BANK_SYNC=true
/// It stays a placeholder until a real implementation exists (see README).
class FeatureFlags {
  FeatureFlags._();

  static const bool bankSync = bool.fromEnvironment('BANK_SYNC', defaultValue: false);
}
