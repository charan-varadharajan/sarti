# Sarti mobile

Flutter app for Sarti on iOS and Android. Stage 2 includes a SQLCipher local
calendar, device/resource keys, encrypted synchronization, explicit conflicts,
recurrence, pickup assignments, and local reminders. A physical device and a
configured WebAuthn RP domain are required to validate passkeys and platform key
storage end to end.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```
