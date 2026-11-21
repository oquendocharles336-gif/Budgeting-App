/// Where the app looks for a newer version: the latest release of your
/// GitHub repository, through the public GitHub Releases API:
///   `https://api.github.com/repos/<OWNER>/<REPO>/releases/latest`
///
/// FILL IN [githubRepository] below as "OWNER/REPO" (the part after
/// github.com/ in your repository's address). The repository must be
/// public, and each release must be published (not a draft or
/// pre-release) with a tag like `v1.2.0`. Attach the APK to the release so
/// the "Download" button opens it directly; without an APK it opens the
/// release page.
///
/// Can also be set at build time without editing code:
///   flutter build apk --release --dart-define=PITAKA_GITHUB_REPO=OWNER/REPO
class AppUpdateConfig {
  AppUpdateConfig._();

  /// "OWNER/REPO". Prefilled from the APK link in the old docs/version.json;
  /// change it if your releases live in another repository.
  static const githubRepository = String.fromEnvironment(
    'PITAKA_GITHUB_REPO',
    defaultValue: 'oquendocharles336-gif/Budgeting-App',
  );

  /// The Releases API address for [githubRepository].
  static Uri get latestReleaseUri => Uri.https('api.github.com', '/repos/$githubRepository/releases/latest');

  /// At most one automatic check per this period ("Check now" ignores it).
  static const checkEvery = Duration(hours: 24);
}
