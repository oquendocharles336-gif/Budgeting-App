# Releasing a new version (APK shared through GitHub Releases)

Users see "Update available" (with your release notes) from the latest
release of your GitHub repository, and "What's new" once after they install
the update.

## One-time setup

1. Open `lib/core/app_update_config.dart` and set `githubRepository` to
   `"OWNER/REPO"` (the part after `github.com/` in your repository's address).
   It is prefilled with `oquendocharles336-gif/Budgeting-App`.
   Or build with `--dart-define=PITAKA_GITHUB_REPO=OWNER/REPO`.
2. The repository must be **public**: the app reads
   `https://api.github.com/repos/OWNER/REPO/releases/latest` without a token.
3. **Keep your release signing key safe and always use the same one.** Android
   only installs an update over the app (keeping users' data) when it's signed
   with the same key. A different key means users must uninstall first and
   lose their data unless they made a backup.

## Every release

1. `pubspec.yaml`: raise the version, e.g. `1.2.0+3` -> `1.3.0+4`.
   The number after `+` must always go up.
2. `lib/core/changelog.dart`: add an entry at the top with the same version
   and build number, and the notes users will see after updating.
3. Build: `flutter build apk --release`
   (file: `build/app/outputs/flutter-apk/app-release.apk`).
4. On GitHub: Releases > Draft a new release.
   - Tag: `v1.3.0` (same version as pubspec; the leading `v` is optional).
   - Notes: the same notes as the changelog. Markdown bullets are shown as
     plain lines (max 30 lines, 300 characters each).
   - Attach the APK (e.g. `pitaka-1.3.0.apk`). Without an `.apk` asset the
     Download button opens the release page instead.
   - Publish it. Drafts and pre-releases are ignored by `/releases/latest`.
5. Phones see it at their next daily check, or right away with
   Settings > App updates > Check now.

## What users can see

- **Up to date**: the installed version is the same or newer than the tag.
- **Update available**: notes, Download (the APK) / Later / Skip this version.
- **Error**: no internet, GitHub's hourly limit for unauthenticated requests
  (60 per network), or no published release (also shown when the repository
  is private or the name is wrong). "Try again" is offered.

## Test it

- Install the old APK, publish a release with a higher tag, open the app:
  "Update available" with your notes. Tap "Skip this version": it doesn't come
  back automatically until a higher tag ("Check now" still shows it).
- Install the new APK over it: "What's new" shows once; data is still there.
  Open the app again: it doesn't show again.
- Airplane mode: the app works normally; "Check now" says "No connection".
