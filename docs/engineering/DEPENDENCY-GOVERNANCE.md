# Dependency governance

## Selection rules

Use the fewest established, maintained dependencies that satisfy an approved
need. Before adoption, review official release source, supported runtime,
maintenance, license, security advisories, native/platform behavior, transitive
dependencies, and privacy impact. Pin direct versions and commit resolver locks.

## Stage 1 selections

Backend: FastAPI, Uvicorn, Pydantic Settings, SQLAlchemy, Psycopg, and Alembic;
development uses Pytest, HTTPX, Ruff, Mypy, Bandit, and pip-audit. Mobile uses
Flutter, Riverpod, and `sqlite3` configured for SQLCipher. Exact resolved versions
live in `backend/pyproject.toml`, `backend/requirements.lock`, and
`mobile/pubspec.lock`.

`sqlite3` downloads checksum-pinned native artifacts via Dart build hooks. Stage
1 selects its SQLCipher community build and verifies the engine at runtime. A
release process must additionally verify published artifact provenance/SBOMs.

## Ongoing controls

CI checks dependency vulnerabilities. Updates are explicit reviewed changes with
tests; automated updates must not merge around failed checks. Material licensing,
security, privacy, or compatibility concerns trigger the contract stop condition.
