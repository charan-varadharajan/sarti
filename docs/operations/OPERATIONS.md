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

Mobile builds connect to a backend only when an HTTPS endpoint is supplied at
compile time; loopback HTTP is accepted for local development. With no value the
calendar remains fully local:

```sh
flutter run --dart-define=SARTI_API_BASE_URL=https://api.example.invalid
```

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

Version validation and increments follow `docs/engineering/RELEASES.md`:

```sh
make version-check version-test
python3 scripts/version.py bump patch
```

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
5. Build the app with `SARTI_API_BASE_URL`, authenticate, and confirm the existing
   bootstrap registers token rotations and forwards foreground lifecycle events.
6. Run the two-device cases in `docs/testing/TEST-STRATEGY.md` before release.

Silent push delivery is opportunistic. Correctness depends on local writes and
foreground encrypted catch-up, never on guaranteed background execution.

## Encrypted replacement-phone recovery (ADR-032)

Migration `0005` adds the bounded durable snapshot table and deletion trigger;
normal container startup runs Alembic before serving traffic. No new provider,
credential, or decryption secret is configured. Owners explicitly upload from
**Encrypted backup**; replacement devices authenticate and discover the snapshot,
then decrypt locally with their user-held phrase. Support cannot recover a lost
phrase. Protocol, retention, integrity checks and retry behavior are documented
in `../api/BACKUP-RECOVERY.md`. Monitor size/availability metadata only; never log
binary bodies, recovery phrases, or key journals. Backup-provider retention and
physical replacement-device acceptance remain release validation requirements.


## Stage 5 scoped membership/audit maintenance (ADR-041 foundation)

With runtime configuration already supplied, run:

```sh
python -m sarti_backend.households.maintenance
```

Or inside the configured local backend container:

```sh
docker compose exec -T backend python -m sarti_backend.households.maintenance
```

The transactional job expires memberships and rotates affected resource epochs,
purges expired encrypted audit entries and five-minute confirmation records, and
emits aggregate counts only. It is retryable; current-request expiry enforcement
also operates independently of this job. Audit access ends at its 30-day deadline.
Production must schedule maintenance at a bounded regular interval (for example,
every five minutes), monitor failures and verify physical purge timing before
release. No scheduler or hosting is activated by this implementation. Provider
backup retention and the separate Stage 5 closure/account purge workflow remain
pending deployment/product work; this command does not implement those workflows.


Stage 5 CI runs both HTTP/Dart hosts in the backend job and the shared native
allowlist on iOS and an isolated Android API 35 x86_64 fixture. Android native
logs and failure screen are retained seven days. The ephemeral fixture is stopped
on success/failure; this does not operate a developer's physical phone. Linux
acceleration is supported by [GitHub's hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners);
headless startup/software rendering follows [Android's emulator CLI](https://developer.android.com/studio/run/emulator-commandline)
and [acceleration documentation](https://developer.android.com/studio/run/emulator-acceleration).
Remote Linux-emulator execution remains unverified until GitHub executes the
updated workflow; local macOS Android tests do not prove that compatibility.
