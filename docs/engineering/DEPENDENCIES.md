# Stage 1 dependencies

Direct versions are pinned in manifests and full resolutions are committed in
lock files. Versions were verified from PyPI, pub.dev, and actual resolver/build
results on 2026-10-11.

| Component | Version | Purpose | License note |
| --- | --- | --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 | iOS and Android framework | BSD-3-Clause |
| flutter_riverpod | 3.4.3 | State/dependency composition | MIT |
| sqlite3 | 3.7.0 | Dart FFI and SQLCipher build hook | MIT; bundled SQLCipher/OpenSSL notices required |
| FastAPI | 0.143.0 | HTTP API | MIT |
| Uvicorn | 0.54.0 | ASGI server | BSD-3-Clause |
| SQLAlchemy | 2.1.3 | PostgreSQL access | MIT |
| Psycopg / binary | 3.3.6 | PostgreSQL driver | LGPL-3.0; preserve distribution obligations |
| Alembic | 1.20.0 | PostgreSQL migrations | MIT |
| Pydantic Settings | 2.15.0 | Typed environment configuration | MIT |
| PostgreSQL container | 17 | Local operational database | PostgreSQL License |

Development tools are pinned in `backend/requirements-dev.txt` and the resolved
`requirements.lock`. SQLCipher is a capability for encrypted local storage; its
presence is not evidence of production key management or E2EE. Before release,
generate complete third-party notices and validate native binary SBOM/provenance.
