/// Where the app looks for a newer version.
///
/// Host a small `version.json` (template: docs/version.json) somewhere
/// public over HTTPS, for example a GitHub repository:
///   https://raw.githubusercontent.com/<your-name>/<repo>/main/version.json
///
/// Set it here, or at build time without editing code:
///   flutter build apk --release --dart-define=PITAKA_UPDATE_URL=https://...
class AppUpdateConfig {
  AppUpdateConfig._();

  static const feedUrl = String.fromEnvironment(
    'PITAKA_UPDATE_URL',
    defaultValue: 'https://raw.githubusercontent.com/YOUR-GITHUB-NAME/pitaka-releases/main/version.json',
  );

  /// False until a real URL is set: then no request is ever made.
  static bool get isConfigured => feedUrl.startsWith('https://') && !feedUrl.contains('YOUR-GITHUB-NAME');

  /// At most one automatic check per this period ("Check now" ignores it).
  static const checkEvery = Duration(hours: 24);
}
