# ADR-040: Safe family recovery continuation (BUG-022)

- Status: Accepted by maintainer on 2026-10-13
- Date: 2026-10-13
- Supersedes: ADR-032's clearing of family historical keys/causal
  history; ADR-039's unconditional family-recovery retention pause only after
  the recovery checks and explicit history review below succeed.
- Preserves: ADR-038 private exclusion/ownership, ADR-020 fresh device identity,
  ADR-021 explicit conflicts, ADR-034 AAD encoding, backup v2 encryption/phrase,
  server backup authorization and seven-day relay retention.

## Evidence and problem

`BackupRecovery.stage` clears `resource_keys`, `event_versions` and
`applied_operations` on the family-only path. The exported encrypted snapshot
contains that information. A replacement device can therefore lose historical
relay decryption capability even after receiving a valid current-epoch key.
Without event vectors, an incoming concurrent change can silently replace a
restored offline edit. The original High-severity defect is reproduced in
../../testing/BUG-022-DESIGN-REVIEW.md; execution evidence is maintained in
../../testing/BUG-022-VERIFICATION.md.

Merely removing three DELETE statements is insufficient. Recovery must preserve
original pending intent without replaying the old device's envelopes, avoid
publishing before catch-up and keep snapshot data separate from live permission.

## Decision

### 1. Preserve content history, never credentials

Family recovery preserves validated, family-scoped historical resource keys,
event/profile vectors, applied-operation IDs, unresolved alternatives, minimal
calendar deletion records and reviewed Keep vectors. These are encrypted
application history, not authority to access a current server resource.

Keep clearing old sessions, device secrets, server cursors, author sequence and
old encrypted retry envelopes. Existing protected-storage activation uses the
new installation's independent device identity/session. Snapshot keys remain
independent of the live phone DB key. Family snapshots continue excluding every
adult-private resource, key, event, conflict and private/shared mapping.

Downloaded historical ciphertext may use a saved older key. New writes/grants
must use the current directory epoch and current server authorization; a saved
key cannot override rotation, reactivate a revoked member/device, resurrect a
deleted resource or grant another adult's private access.

### 2. Separate restored pending intent from outgoing operations

Before discarding the old outbox, preserve its validated unacknowledged mutations
as encrypted recovery intents. Local schema v9 adds a small recovery
state/intent store inside SQLCipher. Keep stable entity/resource IDs, original
payload/vector and a local provenance/dedup identifier; remove session/device
credentials and old nonce/envelope/sequence binding. Never reuse an old accepted
operation UUID for a new authenticated upload. Uploaded history is not requeued.

Coalesce only provably dominated intents for the same entity. Do not select by
wall-clock timestamp or discard concurrent/unknown operations. Keep originals
quarantined if identity, scope or causality cannot be verified. An intentional
pending deletion is an intent too, not permission to erase restored history
before review. Snapshot export can capture the manifest; compatible older v2
snapshots may derive it from their existing encrypted outbox before clearing.

Personal recovery's accepted causal safeguards remain intact. This decision
repairs family continuation; it does not declare unrelated personal pending-write
acceptance complete or weaken that path's scope checks.

### 3. Authenticate and catch up before publishing

Add an explicit family recovery coordinator/state machine:

`restored, paused → refresh current authorization/keys → download available
updates → review recovered changes/conflicts → ready`.

Initialize household access conservatively read-only until the current active
family owner/device and directory are verified. Do not restore cached permission
as authority. Directory refresh during recovery obtains/verifies current grants
but does not provision snapshot resources, widen sharing, republish child/profile
snapshots or enqueue new outgoing work before the recovery gate permits it.

Use a download-only sync pass during catch-up. Validate all encrypted envelopes
and resource scopes as normal; preserve older keys for authenticated historical
messages. Version vectors reject stale/equal updates and preserve concurrent
alternatives. Missing keys, invalid AAD, malformed state or incomplete pagination
keep recovery paused without moving past an unreadable page or erasing local data.

After catch-up, show a parent-facing **Recovered changes** review with conflicts,
restored unsent changes and any authorization failures. The parent explicitly
approves eligible recovered mutations. Only still-current authorized intent is
re-enveloped with a fresh operation UUID, new device sequence, fresh nonce,
current key epoch and advanced replacement-device vector. Atomically record
intent→outbox transition; exact retries persist the new envelope before I/O.
Stable entity IDs and durable transition state prevent duplicate events across
crashes/retries. Never merge a conflicting alternative without review.

New child/resource creation or sharing intent from a snapshot requires fresh
review of current recipients/permissions; old sharing consent cannot silently
include new guardians. Missing/deleted/unauthorized resources remain quarantined,
not automatically recreated. The server independently enforces current resource
permissions, membership, device state, epoch and replay checks on every write.

### 4. Resume retention deliberately

Preserve the recovery pause through staging, activation, authority refresh,
catch-up and unresolved recovery conflicts/intents. Display the family policy
and a preview of expired restored entries. The authorized admin explicitly
selects **Review history and resume cleanup** only after the gate succeeds;
opening the calendar, login or a policy GET alone must not clear the pause.
Future/ongoing appointments and active series remain protected under ADR-039.
Keep decisions and minimal deletion records survive the recovery path.

A stable relay cursor proves only that available messages were processed.
It cannot recover changes that expired beyond seven days or prove the snapshot
is the household's latest complete state. Display snapshot time and that limit;
never label this condition "all household data is up to date". Unavailable newer
history needs an authorized current-state source; this ADR does not invent a new
server plaintext archive or silently extend relay lifetime.

### 5. Legacy/incomplete snapshots and interrupted recovery

Validate required entity vectors and scoped key metadata before writable
activation. Never fabricate causality from timestamps, revisions or device IDs.
An incomplete legacy/re-exported snapshot remains recoverable as preserved
read-only content/quarantined candidate with actionable guidance for an
appropriate authorized snapshot; it cannot enter automatic sync/cleanup.

Persist state transitions in SQLCipher and reuse protected pending-key activation.
Repeated staging/activation/refresh/review must not duplicate intents, drop keys
or change the new installation's identity. Clearing a recovery gate requires
verified checks and explicit review; failure/interruption keeps the gate closed.

## Implementation scope and compatibility

Update recovery export/staging, local schema/migration, scoped validation,
resource-key preparation, sync download-only mode, authenticated bootstrap,
recovered-changes/retention review UI and prepared fixtures. Preserve crypto v2
format and existing backup endpoints. No new service, dependency, permanent
server decryption key or PostgreSQL migration is planned. Reassess that statement
against implementation; any additional accepted-ADR change requires review.

Update backup/key/sync/security/permission/schema/module/API usage documentation,
STATUS, BUGS and CHANGELOG in the implementing change. Do not edit existing
merged migrations. Select version/build increment through ADR-030 before push.

## Required acceptance and security tests

- RECOVERY-CONT-001: independently staged/activated replacement installation
  decrypts old-epoch relay and rejects stale overwrite, with a newer current key.
- RECOVERY-CONT-002: a readable concurrent guardian edit preserves the restored
  unsent alternative and requires explicit conflict resolution.
- RECOVERY-CONT-003: recovered unsent creation/edit/deletion is reviewed and
  published under new device/operation/epoch; duplicate/retry/crash does not
  duplicate events or reuse former credentials/envelopes.
- RECOVERY-CONT-004: owner/current membership/device/epoch checks deny outsiders,
  revoked/replaced devices, stale grants and cross-family/private access.
- RECOVERY-CONT-005: interrupted activation/catch-up/review resumes safely;
  unknown key/AAD or incomplete legacy causality keeps data and gate intact.
- RECOVERY-CONT-006: retention stays paused until explicit authorized review;
  future/active-series/Keep/deletion state survive; genuine conflicts defer it.
- RECOVERY-CONT-007: old snapshot beyond relay TTL reports unavailable history
  accurately; no fake completeness, resource resurrection or silent widening
  of child sharing.

Use prepared encrypted stores and direct target-screen entry. Execute unit/widget,
real SQLCipher/libsodium, API/contract/security, local migration, backup/restore
and native same-platform scenarios. Extend the existing real PostgreSQL/HTTP/Dart
host for current authorization and encrypted continuation. Do not run the
separately unapproved Android→iOS backup portability direction. Physical passkeys,
secure storage, OS interruption and production delivery remain explicit limits.

## Approval and compatibility

Maintainer approved this decision with “sounds good” on 2026-10-13 after reviewing
the concrete design and the two encrypted reproductions. Implementation uses
local schema v9, existing v2 backup envelopes and existing server endpoints;
PostgreSQL remains 0009. Snapshot readers need schema-v9 support for new exports:
pre-1.0 minor increment follows ADR-030. No new dependency or external service.
Incomplete older snapshots remain readable with a blocked recovery gate. Personal
pending-write continuation is outside this fix; its existing safeguards remain.
