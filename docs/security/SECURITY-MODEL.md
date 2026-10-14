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

BUG-004/ADR-035 adds expiring token-only share/copy/QR enrollment. Pending
membership has no content/grant access. Owner review pins the current device
and full public-key digest after both phones compare the displayed code, then
assigns explicit resource permissions. New guardian state is delivered as
separately encrypted family/child/calendar resources above an approval baseline;
no owner backup or plaintext content is shared through the server. Strict link
parsing cannot change the API host or permissions. Client read-only gates and
server authorization are independent. Backend/mobile/cross-layer automated checks pass; BUG-004 is resolved for
automated scope. Physical native share, clipboard,
camera, link and passkey compatibility is not inferred.

## Optional cloud AI boundary — ADR-036

Encryption claims apply to specified storage/sync/backup flows. Optional cloud
AI can disclose minimized scheduling information; it is not E2EE to the model
provider. Fresh labels prevent exporting stable application aliases but do not
guarantee anonymity or prevent schedule/network correlation. Unknown input is
blocked by a conservative token grammar, not a universal PII detector. Version 2
consent defaults off and old consent is not carried forward. Request mappings
stay in memory; source-supported time/recurrence output alone may enrich local
proposals. No automatic event write or cloud fallback is introduced. Backend
credential processing is not implemented; BUG-005 remains open.

`CLOUD-PRIV-001..006` capture outbound payloads, test fresh/repeated identifiers,
Unicode/boundary/ambiguous mappings, unsupported/sensitive/injection input with
zero calls, strict grounded output and local fallback. `CLOUD-CONSENT-002` and
privacy widget coverage verify renewed consent and qualified claims. Provider
handling/network anonymity are not established by these tests.

## Adult-private resources — ADR-038

Owner-wide household permissions exclude personal calendars. Server authorization
checks `private_adult_id` before applying owner bypasses. Listings, device
directories, grants, relay filtering, invitation assignments and replacement
epochs apply this boundary. Personal backups are separately adult-scoped; family
snapshots sanitize private state and compact encrypted pages before packaging.
Historical keys/causal state in an adult's own phrase-encrypted snapshot support
safe personal recovery, not restoration of an old authenticated device identity.
Current keys still require active-device authorization and epoch checks.
A changed household copy cannot be replaced until explicitly reviewed; its exact
vector is rechecked in the atomic save. Local queries/conflict actions exclude
other bound adults' private resources when switching authenticated accounts.
See `../testing/ADR-038-VERIFICATION.md` for executed evidence and gaps.

## Mobile calendar retention (ADR-039)

The server holds a bounded family configuration preference, never the event
content needed to evaluate expiry. Active-device/member and calendar-admin checks
protect policy writes, with optimistic revision conflicts. Cleanup uses normal
resource encryption; minimal IDs/causal state prevent stale resurrection. Pending
edits/open conflicts defer cleanup; explicit Keep/Delete resolves concurrent
retention alternatives without inventing an event. Family snapshot sanitization
also excludes private deletion/conflict rows. Existing encrypted exports/hosted
backups can retain old history; this policy does not erase external copies.
RETENTION-SEC/API/CRYPTO/MIG/RESTORE scenarios cover software boundaries; physical
revocation/background delivery and BUG-022 continuation remain separate limits.

## Family restore continuation controls (ADR-040)

BUG-022 controls cover historical key loss, silent overwrite, unauthorized
republishing, stale grants, resource resurrection and premature retention.
Encrypted family snapshots preserve scoped historical keys/causal state and
quarantined pending intent, excluding private resources. Replacement keeps fresh
credentials, catches up without uploading and requires current owner/resource
authority and explicit review before fresh-epoch publication or cleanup.
Malformed ciphertext cannot advance the failed page cursor; incomplete snapshots
remain readable/blocked. Tests: RECOVERY-CONT/GATE/SCOPE/KEY/MIG plus expanded
GUARD-HTTP real backend host. See BUG-022 verification for actual execution and
physical-device/provider limits; no household-completeness guarantee after TTL.
