# ADR-013: PostgreSQL-backed jobs

- Status: Accepted
- Date: 2026-10-11

Persist background-job state in PostgreSQL. Jobs must be idempotent, retryable,
bounded, observable without sensitive data, and safe under duplicate execution.
The job library and scheduling mechanism remain unresolved.
