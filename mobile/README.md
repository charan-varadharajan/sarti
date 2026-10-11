# Sarti mobile

Flutter bootstrap for Sarti on iOS and Android. Riverpod composes application
dependencies. The Stage 1 startup verifies that the bundled native database is
SQLCipher before any persistent private schema is introduced.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```
