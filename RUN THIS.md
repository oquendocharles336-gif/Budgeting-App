
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
