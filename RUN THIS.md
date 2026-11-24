# Running the App

## Prerequisites (If `flutter: command not found`)
If Flutter is installed at `/home/chachie/development/flutter`, add it to your PATH first:
```bash
export PATH="$PATH:/home/chachie/development/flutter/bin"
```

## Windows (PowerShell)
```powershell
flutter clean
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
flutter pub get
flutter pub outdated
flutter pub upgrade --major-versions
flutter analyze
flutter test
flutter build apk --release
```

## Linux / macOS (Bash)
```bash
flutter clean
rm -rf android/.gradle
flutter pub get
flutter pub outdated
flutter pub upgrade --major-versions
flutter analyze
flutter test
flutter build apk --release
```

## Run
```bash
flutter run --release
```
