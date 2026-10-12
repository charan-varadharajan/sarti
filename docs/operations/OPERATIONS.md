# Operations

## Pinned toolchain through Stage 2

- Flutter 3.47.7 / Dart 3.13.5
- Python 3.13 (validated locally with 3.13.1)
- PostgreSQL 17 container
- Docker 29.6.1 / Compose
- Xcode 27.0 and CocoaPods 1.17.0 for iOS

## Local setup

```sh
cp .env.example .env
make setup
docker compose up --build --wait
curl --fail http://localhost:8000/v1/health/live
curl --fail http://localhost:8000/v1/health/ready
```

`.env` is ignored. Its values are local development placeholders and must be
changed for any shared environment. Runtime settings use the `SARTI_` prefix.

## Checks

```sh
make backend-check
make backend-test
cd backend && SARTI_DATABASE_URL=postgresql+psycopg://USER:PASSWORD@localhost:5433/DB ../.venv/bin/pytest --cov
cd backend && ../.venv/bin/pip-audit -r requirements-runtime.lock
make mobile-check
cd mobile && flutter build apk --debug
cd mobile && flutter build ios --debug --no-codesign
```

Generate OpenAPI with `cd backend && PYTHONPATH=src
SARTI_DATABASE_URL=postgresql+psycopg://unused ../.venv/bin/python
scripts_generate_openapi.py` and commit the result.

## Troubleshooting

- Start Docker Desktop if the daemon socket is unavailable.
- Sarti maps PostgreSQL to host port 5433 because 5432 is commonly occupied;
  override `SARTI_POSTGRES_PORT` if needed.
- Run `flutter doctor -v` for platform tools. Android builds need an accepted SDK
  license plus SDK/NDK components. iOS plugin builds need CocoaPods.
- The observed Flutter SDK runs through Rosetta on this Apple Silicon host; both
  Android and iOS Stage 2 builds succeeded, but native Apple Silicon Flutter is
  preferable when the existing Homebrew layout is corrected.

## Secrets, backup, release, and recovery

Do not commit `.env`, tokens, keys, or credentials. Production secret storage,
hosting, backup/recovery operations, releases, rollback, and incident response
remain unresolved because no production environment exists.
Those runbooks must be approved before their corresponding capability ships.

## Firebase push configuration

Local builds compile without Firebase credentials and the mobile transport
reports unavailable. For a provider/device test environment:

1. Register the Android and iOS application identifiers in the approved Firebase
   project and generate platform configuration with FlutterFire tooling.
2. Keep generated non-secret app configuration environment-specific. Never
   commit an APNs key or Firebase service-account JSON.
3. Enable the iOS Push Notifications signing capability, retain Background Modes
   remote notifications, and upload the APNs authentication key to Firebase.
4. Mount the backend service-account secret as a file and set
   `SARTI_FCM_CREDENTIALS_FILE` to that path.
5. Complete authenticated mobile network bootstrap, construct
   `PushSyncCoordinator` with `SartiApiClient.registerPushToken` and the encrypted
   sync engine, and forward app foreground lifecycle events.
6. Run the two-device cases in `docs/testing/TEST-STRATEGY.md` before release.

Silent push delivery is opportunistic. Correctness depends on local writes and
foreground encrypted catch-up, never on guaranteed background execution.
