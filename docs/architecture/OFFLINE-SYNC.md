# Offline synchronization

ADR-021 defines the implemented Stage 2 protocol. The SQLCipher database is the
authoritative store. An event or child-profile mutation and its outbox row commit together; the UI
does not wait for a network response.

## Envelope and ordering

Each upload contains an operation UUID, family/resource UUIDs, author device UUID,
strictly increasing device sequence, resource-key epoch, version vector, 24-byte
nonce, ciphertext, and SHA-256 digest of nonce plus ciphertext. XChaCha20-Poly1305
authenticates protocol version and all routing/version fields as additional data.
The server validates the active session, membership, resource permission, key
epoch, size, digest, operation ID, and exact next device sequence.

The encrypted envelope is persisted inside SQLCipher before upload. An exact
retry of every accepted envelope field, digest, author, and sequence receives
the existing receipt. Reuse with different data, gaps, rollbacks, malformed
fields, new operations with stale epochs, and unauthorized resources fail closed. Downloads use a
monotonic server cursor and never rely on wall-clock ordering.

## Conflicts and retention

Version vectors classify operations as newer, stale/equal, or concurrent.
Concurrent event edits are stored in the encrypted local database as an open
conflict with both alternatives and both vectors. The calendar shows a conflict
badge and requires the guardian to choose a version. Resolution merges both
vectors, advances the resolving device counter, and emits another encrypted
operation. Neither alternative is silently selected.

Relay rows expire exactly seven days after first receipt. Upload and download
transactions delete expired rows, and reads exclude expired rows. A device offline
past retention needs a snapshot from another authorized device; snapshot transfer
is unresolved and is not represented as implemented.

## Failure behavior

Failed uploads remain pending. Accepted uploads are marked only after the receipt.
Duplicate downloads are ignored by operation UUID. Digest failure, missing key
epoch, or authentication-tag failure stops processing without applying content.
The authenticated bootstrap wires family provisioning, resource-key exchange,
ordered encrypted uploads, foreground catch-up, and push hints. Provider and
physical-device networking/background scheduling remain validation gaps.

## Child profiles (BUG-003)

`child_created` payloads contain exactly `id`, `householdId`, `name`, `colorArgb`
and `cloudAlias`, inside child-resource ciphertext. A stable child UUID is its
resource UUID. The receiver checks the authenticated family, resource kind,
payload identity, field types/bounds and alias rules before committing the
profile and operation ID together. Identical profiles converge; a conflicting
creation with the same ID fails closed, preserving the existing row and cursor.
Child-profile editing is not implemented by this creation operation.

Calendar assignments contain opaque child IDs. If the separate profile is not
readable or has not arrived, a hidden nameless placeholder preserves the foreign
key; the calendar displays a generic colour without inferring a child's name.
Later authenticated child delivery replaces the placeholder atomically. Child
content is never copied into calendar-resource plaintext or server metadata.

The resource directory and grant checks are detailed in
[child synchronization](CHILD-PROFILE-SYNC.md). Filtered pages may be empty with
an advanced cursor. Subsequent sync passes continue paging; newly granted keys
reset the local cursor to replay retained operations. Seven-day relay retention
still applies: grants cannot recreate expired profiles; the approved encrypted
snapshot/recovery path is required beyond retention.

If a key rotates while an upload is pending, an exact previously accepted
old-epoch envelope can still obtain its receipt under current write authorization;
this stores no new ciphertext. An unaccepted stale envelope is rejected. With
the new key available, the client then re-authenticates its unchanged local
payload under the current epoch, retaining operation ID and device sequence.
`CHILD-SYNC-006` tests both interruption cases. Missing historical keys still fail
closed; a newly enrolled/recovered device needs a suitable encrypted snapshot
rather than silently skipping unknown-epoch operations.

## Versioned metadata (BUG-011 / ADR-034)

New envelopes authenticate protocol 2 using the fixed field order and sorted
logical-version keys specified in ADR-034. Relay `protocol_version` is stored
and included in exact-retry comparison. Protocol 1 remains insertion ordered;
existing ciphertext and pending envelope bytes are never relabeled. New local
payloads are encrypted with protocol 2; stored legacy envelopes without a
version retry as protocol 1. Unknown versions/tampering fail without fallback.
An already reordered legacy multi-author envelope cannot safely be reconstructed;
retain local content/cursor and recover from authorized snapshot/original author
data. Migration 0006 preserves existing ciphertext with version 1; downgrade
refuses to remove version tags while protocol-2 rows exist. Deploy backend first.

## ADR-038 routing

Adult private writes use the bound personal resource; household sharing creates
an independent event and queues both atomically. Private/shared mappings stay
local. Changed household vectors require explicit exact-version review before
replacement. Typed participant references and `participant_upserted` payloads
use separately granted shared profile resources. `child_updated` uses durable
child vectors. Identical concurrent child snapshots merge causality; different
edits fail closed. Restored events retain causal state on the personal recovery
path; apply compares persisted vectors even when the previous outbox was cleared.
Old clients do not understand these new operation kinds/local schema and must
upgrade together with backend migration 0008 for this private beta contract.
