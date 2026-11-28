
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
export PATH="$PATH:/home/chachie/development/flutter/bin"
flutter clean
rm -rf android/.gradle
flutter analyze
flutter pub outdated
flutter pub upgrade --major-versions
flutter pub get
flutter test
flutter build apk --release
```

## Run
```bash
flutter analyze
flutter test
flutter pub upgrade --major-versions
flutter pub get
flutter run --release
```
