# ADR-034: Versioned deterministic synchronization metadata encoding

- Status: Accepted
- Date: 2026-10-12
- Approval: Maintainer approved the BUG-011 versioned deterministic encoding and
  compatibility proposal with “ok-fix”.
- Supersedes: ADR-020/021 metadata serialization detail only; crypto, permission,
  epoch, sequence, retention and explicit conflict guarantees are unchanged.

## Decision

New operations use protocol 2. Additional authenticated data is compact UTF-8
JSON with these fields in fixed order: `protocol`, `familyId`, `resourceId`,
`keyEpoch`, `operationId`, `authorDeviceId`, `deviceSequence`, `logicalVersion`.
The version map is serialized in ascending string-key order, using unchanged
UUID strings and integer counters. No whitespace or alternate encoding is used.
There are no floating-point numbers or private content in this metadata.
The same encoder is used for encryption and decryption. XChaCha20-Poly1305 and
random nonces remain provided by libsodium; this is serialization, not a new
cryptographic primitive. No dependency is added.

The relay persists `protocol_version` (1 or 2), includes it in downloads and
idempotency comparison, and defaults absent values to 1 for old clients/rows.
The authenticated `protocol` field matches this version. Unknown versions fail
closed; protocol-2 authentication never retries with protocol 1.

## Compatibility and rollout

Deploy the additive backend migration/API first, then updated clients. Legacy
clients cannot decode protocol 2 and must be upgraded for mixed-author sync.
Existing protocol-1 ciphertext is never relabeled or rewritten during migration.
Persisted pending envelopes without a version remain protocol 1 and retry exact
bytes. Unencrypted pending local payloads use protocol 2 when first encrypted.
Existing stale-epoch re-encryption applies only after rejection, preserving the
operation ID/sequence and pending payload; accepted receipts stay idempotent.

Protocol-1 decoding preserves its original fixed top-level/insertion-ordered
version-map encoding. Single-author legacy vectors remain readable. If a legacy
multi-author vector has already lost its original order in JSONB, the decoder
fails closed, preserves local data and cursor, and requires an authorized
snapshot/original author data for recovery. It does not guess permutations,
discard conflicting alternatives or bypass authentication. This change prevents
new reordered-vector failures; it cannot reconstruct irreversibly lost bytes.

## Required evidence

Known metadata byte vectors, reversed map order, all metadata tampering, unknown
versions, legacy reading/exact pending retry, durable conflict alternatives,
version-aware duplicate rejection, migration preservation of legacy ciphertext,
and real Dart encryption → HTTP → PostgreSQL JSONB → HTTP → Dart decryption.
Physical device/provider compatibility is separate from these tests.
