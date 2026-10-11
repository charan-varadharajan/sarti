# Sarti

Sarti is a privacy-first AI family organizer: **Your family's wise companion.**

This monorepo contains the Flutter iOS/Android app, FastAPI backend, PostgreSQL
migrations, Docker local environment, tests, CI gates, and architecture/security
documentation established in Stage 1.

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
