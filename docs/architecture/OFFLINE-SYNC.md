# Offline synchronization

## Approved constraints

The encrypted local database is authoritative for offline work. Devices exchange
resource-scoped authenticated ciphertext through a server relay. Conflicts resolve
deterministically and converge. Relay ciphertext expires after seven days.

## Protocol requirements

The eventual design must cover stable operation and resource IDs, idempotency,
authenticated ordering metadata, replay and rollback protection, duplicate and
out-of-order delivery, tombstones, membership/key changes, clock independence,
pagination, acknowledgement, expiry, and interrupted local commits.

## Stage 1 boundary

No synchronization protocol, envelope, merge rule, or relay table is implemented.
Selecting one without a reviewed ADR would invent an unapproved security design.
