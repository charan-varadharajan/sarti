# Data flows

## Implemented in Stage 1

1. A client requests `GET /v1/health/live`; the API returns process status and a
   correlation ID without accessing data.
2. A client requests `GET /v1/health/ready`; the API executes `SELECT 1` against
   PostgreSQL and returns availability without exposing connection details.
3. The mobile bootstrap opens an in-memory SQLCipher database, verifies
   `cipher_version`, supplies a test-only key, and closes it.

## Approved but not implemented

Local edits, encrypted synchronization, AI suggestions, email intake, push
wake-ups, backup/restore, export, and deletion follow the flows summarized in
`ARCHITECTURE.md`. Their formats and product contracts remain unresolved and no
Stage 1 bootstrap may be interpreted as implementing them.
