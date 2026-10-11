# ADR-003: SQLite and SQLCipher local storage

- Status: Accepted
- Date: 2026-10-11

Persist private family content locally in SQLite encrypted by SQLCipher. Startup
must verify `PRAGMA cipher_version` and fail closed when SQLCipher is absent.
Key custody, schema, migrations, and recovery behavior remain unresolved.
