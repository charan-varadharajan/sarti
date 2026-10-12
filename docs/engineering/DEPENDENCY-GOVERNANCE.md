# Dependency governance

## Selection rules

Use the fewest established, maintained dependencies that satisfy an approved
need. Before adoption, review official release source, supported runtime,
maintenance, license, security advisories, native/platform behavior, transitive
dependencies, and privacy impact. Pin direct versions and commit resolver locks.

## Selections through Stage 3

Backend: FastAPI, Uvicorn, Pydantic Settings, SQLAlchemy, Psycopg, and Alembic;
development uses Pytest, HTTPX, Ruff, Mypy, Bandit, and pip-audit. Mobile uses
Flutter, Riverpod, `sqlite3` configured for SQLCipher, libsodium, platform secure
storage and local authentication, native passkeys, IANA timezone data, local
notifications, and SHA-256 support. The backend adds the maintained Python
`webauthn` verifier. Exact resolved versions live in the backend requirement
locks and `mobile/pubspec.lock`.

Stage 3 adds `firebase-admin` for opaque push wake-ups and
`google_generative_ai` for an optional locally pseudonymized cloud adapter. The product
owner explicitly approved this exception and reaffirmed it on 2026-10-11. It
remains blocked from production use until the app provides clear disclosure and
explicit opt-in and provider data handling is verified.

`sqlite3` downloads checksum-pinned native artifacts via Dart build hooks. Sarti
selects its SQLCipher community build and verifies the engine at runtime. A
release process must additionally verify published artifact provenance/SBOMs.

## Ongoing controls

CI checks dependency vulnerabilities. Updates are explicit reviewed changes with
tests; automated updates must not merge around failed checks. Material licensing,
security, privacy, or compatibility concerns trigger the contract stop condition.
