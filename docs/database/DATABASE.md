# Database documentation

## Stores

- Local: SQLite linked to SQLCipher through the Dart `sqlite3` build hook. Stage 1
  verifies the engine but introduces no persistent content schema.
- Server: PostgreSQL 17 for operational metadata. Stage 1 contains only the
  operational `schema_metadata` table.

See `LOCAL-DATABASE.md` and `SERVER-DATABASE.md` for fields, classifications, and
boundaries.

## Migration history

| Revision | Store | Change | Upgrade/downgrade tested |
| --- | --- | --- | --- |
| `0001` | PostgreSQL | Create `schema_metadata`; insert schema version 1 | Yes |

Alembic runs `0001` automatically when the backend container starts. The
integration suite verifies head upgrade, full downgrade, and re-upgrade against
PostgreSQL. Local content migrations begin only after the content model and key
management design are approved.
