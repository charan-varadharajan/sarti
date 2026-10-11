# ADR 0005: Server persistence, relay retention, and jobs

- Status: Accepted
- Date: 2026-10-11

## Decision

PostgreSQL stores server operational metadata, authorization state,
PostgreSQL-backed background jobs, and encrypted relay payloads. Relay ciphertext
has a seven-day retention limit. Server authorization is role based and resource
scoped. One active phone per adult is enforced by the backend.

## Consequences

Cleanup requires observable, retryable jobs and database-enforced expiry data.
Every query path requires family scoping and negative isolation tests. Device
replacement must revoke the prior active device for future server access.
