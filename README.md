# Sarti

Sarti is a privacy-first AI family organizer: **Your family's wise companion.**

Calendar sync and backups use encrypted content. Native AI runs on-device;
optional cloud AI, when explicitly requested and enabled, temporarily processes
limited scheduling information on Sarti servers and Google Gemini with temporary labels. This reduces exposure but does
not make it anonymous. Inbound email has a separate plaintext-processing
boundary. See [privacy disclosure](docs/PRIVACY.md). The broker is implemented disabled by default. Native AI and the local parser
remain the primary path; live cloud validation is deferred.

This monorepo contains the Flutter iOS/Android app, FastAPI backend, PostgreSQL
migrations, Docker local environment, tests, CI gates, and architecture/security
documentation through Stage 2.

Current development version: `0.5.0` (mobile build `5`; no public release tag). Version increments and
release tags follow [ADR-030](docs/architecture/adr/030-release-versioning.md).

## Prerequisites

- Flutter 3.47.7 with Dart 3.13.5
- Python 3.13
- Docker Desktop with Docker Compose
- Xcode 27 and CocoaPods 1.17 for local iOS builds
- Android SDK 36 for local Android builds

## Start the backend

```sh
cp .env.example .env
docker compose up --build --wait
curl http://localhost:8000/v1/health/live
curl http://localhost:8000/v1/health/ready
```

PostgreSQL is exposed on host port `5433` by default to avoid common local port
conflicts. The API is exposed on `8000`.

## Verify the repository

Quick local Flutter tests (from this directory):

```sh
./test             # unit/widget tests, no device needed
./test --ios       # prepared calendar/child/grid UI journeys on an iOS simulator
./test --android   # prepared calendar/child/grid UI journeys on an Android emulator
```

Console shows pass/fail; logs are saved in `test-results/`. The runner starts an
installed simulator/emulator if needed. See
[scenario instructions](docs/testing/TEST-SCENARIOS.md) for individual journeys
and coverage limits. Backup portability is excluded from these shortcuts.

Full repository gates:

```sh
make setup
make backend-check
make backend-test
make mobile-check
```

PostgreSQL integration tests use the database URL in `SARTI_DATABASE_URL`.
See [operations](docs/operations/OPERATIONS.md)
for all commands and troubleshooting.

## Required reading

Read `AGENTS.md` and every mandatory document it links before changing code.
The current stage and unresolved security decisions are in `docs/STATUS.md`.
