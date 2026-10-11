# ADR-007: Offline-first encrypted synchronization

- Status: Accepted; protocol unresolved
- Date: 2026-10-11

The encrypted local store is the mobile source of truth and P0 calendar actions
work offline. Devices exchange resource-scoped ciphertext through the server.
Conflict resolution must converge deterministically. Ordering, replay defense,
tombstones, and merge rules remain unresolved.
