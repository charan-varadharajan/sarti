# ADR 0003: Offline-first encrypted synchronization constraints

- Status: Accepted; protocol pending
- Date: 2026-10-11

## Decision

The encrypted local database is the mobile source of truth. Users can perform P0
calendar work offline. Devices synchronize resource-scoped ciphertext through a
server relay that cannot read family content. Conflict handling must be
deterministic and converge across devices.

## Consequences

Operations require stable identities, replay protection, authenticated ordering
metadata, idempotency, deletion semantics, and bounded tombstone retention. Their
exact design remains open and must be approved before sync implementation.
