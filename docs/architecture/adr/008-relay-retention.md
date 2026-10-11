# ADR-008: Seven-day ciphertext relay retention

- Status: Accepted
- Date: 2026-10-11

Server relay ciphertext expires seven days after receipt. Expiry is represented
in PostgreSQL and enforced by retryable cleanup jobs. Whether acknowledged items
may be deleted earlier is unresolved.
