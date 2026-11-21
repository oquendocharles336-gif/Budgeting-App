# Releasing a new version (APK shared directly)

Users see "Update available" (with your notes) from a small `version.json`
you host, and "What's new" after they install the update.

## One-time setup

1. Create a **public** GitHub repository, e.g. `pitaka-releases`.
2. Put `docs/version.json` in it (root, branch `main`).
3. Set the address in `lib/core/app_update_config.dart`:
   `https://raw.githubusercontent.com/<your-name>/pitaka-releases/main/version.json`
   (or build with `--dart-define=PITAKA_UPDATE_URL=<that address>`).
4. **Keep your release signing key safe and always use the same one.** Android
   only installs an update over the app (keeping users' data) when it's signed
   with the same key. A different key means users must uninstall first and
   lose their data unless they made a backup.

## Every release

1. `pubspec.yaml`: raise the version, e.g. `1.1.0+2` -> `1.2.0+3`.
   The number after `+` must always go up.
2. `lib/core/changelog.dart`: add an entry at the top with the same version
   and build number, and the notes users will see after updating.
3. Build: `flutter build apk --release`
   (file: `build/app/outputs/flutter-apk/app-release.apk`).
4. Optional checksum (PowerShell): `Get-FileHash app-release.apk -Algorithm SHA256`
5. On GitHub: create a Release tagged `v1.2.0` and attach the APK
   (rename it e.g. `pitaka-1.2.0.apk`).
6. Edit `version.json` in the releases repo:
   - `latestVersion`: "1.2.0", `latestBuild`: 3
   - `apkUrl`: the release asset link (must start with https://)
   - `notes`: the same notes as the changelog (max 30 lines, 300 characters each)
   - `sha256`: the checksum from step 4 (64 hex characters), or leave empty
   - `minSupportedBuild`: only raise it if old versions must update
     (they then see "Update needed" with no "Skip")
7. Commit. Phones see it at their next daily check, or right away with
   Settings > App updates > Check now (GitHub may cache the file for ~5 minutes).

## Test it

- Install the old APK, set `latestBuild` higher than its build, open the app:
  "Update available" with your notes. Tap "Skip this version": it doesn't come
  back until a higher `latestBuild`.
- Install the new APK over it: "What's new" shows once; data is still there.
- Airplane mode: the app works normally and shows nothing.
