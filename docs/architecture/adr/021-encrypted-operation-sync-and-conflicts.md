# ADR-021: Encrypted operation sync and conflicts

- Status: Accepted
- Date: 2026-10-11

The SQLCipher database is authoritative. A local calendar mutation and its
outbox operation commit in one transaction before network work begins. Outbox
items upload in author-device sequence order. Retrying the same operation ID and
digest returns the existing result; reusing an operation ID or accepted sequence
with different content is rejected as a replay.

The server validates the session, active device, family membership, resource
permission, envelope bounds, key epoch, operation uniqueness, and sequence. It
stores authenticated metadata plus opaque ciphertext for seven days. It cannot
decrypt operations. Downloads use an opaque server cursor and are restricted to
active devices with resource permission.

Each local resource record carries a version vector. A causally newer operation
is applied; a causally older or duplicate operation is ignored. Concurrent edits
create a durable conflict containing both encrypted alternatives and neither is
silently selected. The user chooses one alternative or saves a merged value. A
resolution operation references both parent operation IDs and advances the
version vector, causing all authorized devices to converge.

Malformed envelopes, invalid authentication tags, unknown key epochs, sequence
replays, unauthorized resources, and operations above the documented size limit
fail closed. Relay cleanup is idempotent and removes rows at `expires_at`, seven
days after first receipt. A device offline beyond relay retention requires an
encrypted snapshot from another authorized device or a future approved backup;
the server cannot recreate expired family content.

