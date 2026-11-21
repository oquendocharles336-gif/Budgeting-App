Before running

```bash
flutter pub get
flutter pub outdated
flutter pub upgrade --major-versions
flutter analyze
flutter test
```

```bash
flutter run --release
```

Generate the  apk
```bash
flutter clean
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
flutter pub get
flutter build apk --release
```