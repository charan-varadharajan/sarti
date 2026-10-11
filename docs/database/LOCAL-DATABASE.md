# Local SQLite and SQLCipher design

Stage 1 bundles SQLCipher through `sqlite3` 3.x build hooks and verifies
`PRAGMA cipher_version` before use. The check fails closed if ordinary SQLite is
loaded. The bootstrap uses an in-memory database and a test-only key; no private
content schema or production key storage exists.

Future documentation must list every table, column, constraint, index, migration,
retention rule, and data classification. Migration tests must cover encrypted
upgrade, interruption, rollback behavior, and wrong-key/corrupt-file failures.
