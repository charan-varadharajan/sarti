# Offline synchronization

ADR-021 defines the implemented Stage 2 protocol. The SQLCipher database is the
authoritative store. An event mutation and its outbox row commit together; the UI
does not wait for a network response.

## Envelope and ordering

Each upload contains an operation UUID, family/resource UUIDs, author device UUID,
strictly increasing device sequence, resource-key epoch, version vector, 24-byte
nonce, ciphertext, and SHA-256 digest of nonce plus ciphertext. XChaCha20-Poly1305
authenticates protocol version and all routing/version fields as additional data.
The server validates the active session, membership, resource permission, key
epoch, size, digest, operation ID, and exact next device sequence.

An exact retry of an accepted operation ID, digest, author, and sequence receives
the existing receipt. Reuse with different data, gaps, rollbacks, malformed
fields, stale epochs, and unauthorized resources fail closed. Downloads use a
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
The current Stage 2 engine provides the protocol and simulation coverage; wiring
the relay to a real device/network and background scheduling remains a real-device
integration gap.
