# Security model

Status: Stage 2 identity, authorization, device-key, encrypted-relay, and local
calendar controls are implemented under ADR-019 through ADR-022. Stage 3 privacy
remediation includes the approved ADR-031/032 recovery fixes. Open product
defects and provider/physical-device validation remain in `docs/STATUS.md`.

The backend implements passkeys, one-active-device enforcement, owner/guardian
membership, resource permissions, signed sealed key grants, replay defense, and
a seven-day ciphertext relay. Mobile implements SQLCipher persistence, platform
secret storage/user-presence gating, resource encryption, local-first outbox,
version-vector conflicts, and generic local reminder text. Stage 3 adds parser,
email-ingest, push-dispatch/client, and backup modules, but Stage 3 is not release-ready:
the approved pseudonymized cloud assist has a versioned local disclosure and
opt-in but provider configuration remains unverified. The native proposal flow
is integrated: it runs the deterministic parser first, runtime-gates Apple or
Android on-device inference, treats output as untrusted, fills unresolved fields
only, and requires confirmation. Email plaintext exists only within the external
gateway and backend request-processing boundary; the backend persists one
libsodium sealed-box ciphertext per active device. The mobile app decrypts and
reviews these suggestions locally. The push client accepts only the exact opaque
payload, coalesces sync hints, and is connected to authenticated sync bootstrap.
Provider and physical-device validation remain outstanding.
Account/family deletion remains unimplemented.

## Protected assets

- Family profiles, calendar content, pickup assignments, and suggestions
- Account, family membership, and device authorization state
- Resource keys, device keys, backup keys, recovery material, and passkeys
- Email contents during the documented plaintext processing window
- Availability and integrity of synchronization and deletion

## Adversaries and failure cases

- A network attacker
- A compromised or curious server operator
- A user attempting cross-family access
- A revoked, replaced, lost, or stolen device
- A malicious email sender or prompt-injection payload
- A compromised push, email, telemetry, or backup provider
- Replay, reordering, duplication, rollback, and tampering of sync messages
- Accidental sensitive logging or analytics collection

An unlocked, fully compromised authorized device can expose content already
available to it. Revocation protects future access and is not remote erasure.

## Security invariants

- Server persistence contains no plaintext private family content.
- All endpoints authenticate and authorize the adult, active device, family, role,
  and resource where applicable.
- Cross-family identifiers never grant access by possession alone.
- Ciphertext is authenticated; corrupted or replayed operations fail safely.
- Key material is never logged and is not included in backups without encryption.
- Push payloads and URLs do not contain sensitive data.
- Remote push is only an untrusted hint; authorization, replay defense, content
  authentication, and decryption remain in the normal sync protocol.
- AI output and inbound email are untrusted input.
- Generated changes require explicit approval.
- Native AI failure or unavailability falls back locally and never silently
  invokes cloud inference.
- Secrets come from runtime configuration and never source control.

## Key lifecycle

ADR-020 and `../architecture/KEY-MANAGEMENT.md` specify the implemented device/resource lifecycle.
Guardian removal increments every resource epoch and prevents future grants.
BUG-010 is resolved: device replacement advances accessible live resource
epochs in the same transaction as revocation and fresh session creation.
Serialized resource publication and current-device checks reject stale writes
and revoked granters. Full backend/mobile automated regression and security
checks pass; physical passkey/protected-storage and production two-phone
validation remain required before release. See
`../testing/BUG-010-VERIFICATION.md` for evidence and limits.
Backup derivation is independent of sync keys. Approved ADR-032 encrypts the
SQLCipher key inside the v2 snapshot envelope and gates the durable server blob
to active family owners. Login permits download but never decryption. Local
restore verifies family/schema/integrity, preserves new device identity, clears
old sync credentials/state, and activates via a protected retryable journal.

## Authentication and device authorization

Passkeys authenticate adults. Device biometrics gate local access but are not a
server identity. The backend records at most one active phone for each adult and
rejects inactive or replaced devices. Account recovery must not silently weaken
content encryption or allow the server to reconstruct private keys.

## Email boundary

External mail is plaintext in transit to and during initial gateway processing.
Cloudflare, retention, logging, attachment rejection, size limits, injection
defenses, and the encryption boundary are specified in ADR-024. The boundary
ends when the backend seals the bounded JSON payload to active device public
keys. PostgreSQL stores no sender, subject, body, or server-decryptable content.

## Logging and monitoring

Allow bounded operational fields such as request ID, coarse result code, duration,
service version, and pseudonymous identifiers with documented retention. Deny
content, email bodies, names, event text, tokens, keys, raw ciphertext, passkey
material, notification text, and unbounded exception payloads.

## Required security verification

- Cross-family and role/resource authorization abuse tests
- Replaced-device and revoked-device tests
- Replay, tampering, rollback, duplicate, and malformed-ciphertext tests
- Key creation, storage, rotation, recovery, backup, and deletion tests
- Email parser and prompt-injection tests
- Log, telemetry, URL, and push-payload disclosure tests
- Dependency, static analysis, and secret scanning

## Open security decisions

Provider production configuration, AI compatibility on physical devices, the
physical backup/recovery validation, deletion deadlines, production RP domain,
device-attestation policy, and metadata retention beyond the seven-day relay
rule require approval or later implementation. Physical-device validation is
required before release.

## BUG-003 control coverage

| Control | Automated evidence |
| --- | --- |
| Stable child identity, private content excluded from resource requests, explicit sharing, no retry-based permission expansion | `backend/tests/integration/test_child_sync_api.py`; `mobile/test/child_sync_api_client_test.dart` |
| Cross-family, owner/resource permissions, pending/revoked devices and granters | PostgreSQL child API journey; mobile `CHILD-SEC-001/002` |
| Signed recipient-bound sealed keys, wrong-device/tamper/stale-epoch rejection, no conflicting-key overwrite | `CHILD-SEC-001/005`; grant API negative cases |
| Rotation convergence, single established epoch, no future key to revoked recipient | `CHILD-SYNC-004`; serialized PostgreSQL grant tests |
| Child/calendar resource separation and malformed/cross-family payload rejection | `CHILD-SEC-003/004`; expected local resource catalog |
| Lost receipt, duplicates, reordered event/profile, offline survival and permission-late replay | `CHILD-SYNC-001/002/005/006`; filtered relay API pages |
| Encrypted migration preserves child/event/pending data and rejects wrong key | `CHILD-MIG-001` plus native SQLCipher scenario |

Tests use synthetic family content and independent device keys. Controlled
relay/native simulator tests do not establish physical secure-storage policies,
production passkeys or provider delivery. Child creation conflicts fail closed;
there is no child-profile editing protocol or automatic overwrite path.

BUG-011 is resolved under approved ADR-034. New operations use versioned
deterministic metadata, preserving meaning across PostgreSQL JSONB ordering.
Existing encrypted data and legacy pending retries remain unchanged. There is
no cross-version authentication fallback: unknown versions and changed fields
fail closed. Full Flutter/backend and real HTTP/PostgreSQL/Dart crypto checks
pass on 2026-10-13; see `../testing/BUG-011-VERIFICATION.md`.
Already-lost legacy ordering requires authorized recovery and is not guessed.
Physical-device claims remain separate; BUG-017 conflict-card retirement is
still outstanding.
