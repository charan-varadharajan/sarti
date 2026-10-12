# Child profile synchronization — BUG-003

Implements accepted ADR-020, ADR-021 and ADR-022. No ADR changes, provider,
cryptographic primitive, dependency or server content table is introduced.

## User journey and permissions

The parent opens the existing calendar and adds a child. Name, private AI alias
and colour save immediately to SQLCipher with a `child_created` outbox entry.
The optional **Share profile with current calendar guardians** checkbox defaults
to off. Checking it records explicit owner consent to read-only child access for
active calendar guardians when first provisioned. Later guardians are not added
by retrying creation. Other owners' families, pending members and inactive
devices receive no grants. This shares with existing authorized guardians;
invitation/approval onboarding remains BUG-004.

Local legacy profiles are provisioned/queued once, with no inferred sharing
consent. Subsequent permission administration belongs to the BUG-004 journey.
The owner-only server endpoint rejects guardian-created resources.

## Components and data flow

1. `CalendarRepository.addChild` atomically saves a profile, its operation and
   consent marker. Network availability is not a prerequisite.
2. `ResourceKeySync.prepare` discovers registered resources, persists a random
   key for a new child, provisions the stable UUID and resolves authorized devices.
3. Signed libsodium sealed-box grants are exchanged and verified. Only routing
   UUIDs, public keys, permissions, epochs and sealed keys cross this boundary.
4. `SyncEngine` stores an exact retry envelope locally, uploads authenticated
   ciphertext and decrypts authorized downloads with the expected resource kind.
5. `applyRemoteChild` validates and commits the profile plus deduplication marker.
   Controller refresh makes its name/colour available in the receiving calendar.

```mermaid
sequenceDiagram
    participant P as Parent calendar
    participant L as SQLCipher / outbox
    participant S as Authorized metadata and ciphertext relay
    participant G as Authorized guardian device
    P->>L: Save child + explicit sharing choice atomically
    L->>S: Stable resource UUID + optional read consent
    L->>S: Signed sealed key grants; encrypted child operation
    G->>S: Authenticated resource directory / own grants / relay
    S-->>G: Authorized public metadata and ciphertext only
    G->>G: Verify admin/signature/scope; decrypt; validate
    G->>G: Commit child + operation ID; refresh calendar
```

## Security and failure behavior

Keys are independent of the calendar key. A calendar writer cannot impersonate a
child-profile operation: the local resource catalog must identify a child
resource, and encrypted payload IDs must match authenticated routing metadata.
Malformed content, tampered tags/grants, unavailable keys and conflicting profile
creations stop processing without overwriting private state or advancing the
page cursor. Event assignment placeholders contain no inferred profile data.
Newly received keys reset the cursor to recover retained profiles skipped before
permission delivery; operation IDs prevent duplicate application.

A recipient/epoch grant is unique. Exact retries are idempotent; conflicting
sealed keys are rejected. A resource lock selects the first epoch granter, and
subsequent admins must receive its key before publishing more grants. Concurrent
rotation tests check convergence. Revoked devices and granters are excluded from
grants; already copied historical data cannot be erased remotely.

## Boundaries and verification

See [verification report](../testing/BUG-003-VERIFICATION.md),
[scenario catalogue](../testing/TEST-SCENARIOS.md),
[key lifecycle](KEY-MANAGEMENT.md), and [API contract](../api/API.md).
SQLCipher schema v6 adds local coordination/retry records. PostgreSQL remains at
migration 0005. The seven-day relay is not a permanent snapshot: a device offline
past retention needs approved backup/recovery and fresh grants. Physical
passkeys, protected storage, provider networking and new-guardian onboarding are
not established by controlled relay fixtures.

Pending-upload rotation is covered separately: current-authorized clients first
retry the exact old envelope for an existing receipt; a rejected unaccepted
stale envelope is re-encrypted under the current key using the same operation ID
and sequence. New stale-key content is never accepted. Unknown historical keys
still require snapshot recovery; they are not bypassed by dispatch logic.
