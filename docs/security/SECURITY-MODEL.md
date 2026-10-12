# Security model

Status: Stage 2 identity, authorization, device-key, encrypted-relay, and local
calendar controls are implemented under ADR-019 through ADR-022. Stage 3 code is
present but failed the 2026-10-11 privacy and acceptance audit.

The backend implements passkeys, one-active-device enforcement, owner/guardian
membership, resource permissions, signed sealed key grants, replay defense, and
a seven-day ciphertext relay. Mobile implements SQLCipher persistence, platform
secret storage/user-presence gating, resource encryption, local-first outbox,
version-vector conflicts, and generic local reminder text. Stage 3 adds parser,
email-ingest, push-dispatch, and backup modules, but they are not release-ready:
the approved pseudonymized cloud assist has a versioned local disclosure and
opt-in but provider configuration remains unverified, email content is persisted
as server plaintext, the mobile acceptance flows are not
integrated, and provider and physical-device validation is outstanding.
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
- AI output and inbound email are untrusted input.
- Generated changes require explicit approval.
- Secrets come from runtime configuration and never source control.

## Key lifecycle

ADR-020 and `KEY-MANAGEMENT.md` specify the implemented device/resource lifecycle.
Guardian removal increments every resource epoch and prevents future grants.
Backup derivation and recovery remain unresolved and do not reuse sync keys.

## Authentication and device authorization

Passkeys authenticate adults. Device biometrics gate local access but are not a
server identity. The backend records at most one active phone for each adult and
rejects inactive or replaced devices. Account recovery must not silently weaken
content encryption or allow the server to reconstruct private keys.

## Email boundary

External mail is plaintext in transit to and during initial gateway processing.
Implementation must document the provider, retention, subprocessors, log
redaction, deletion, abuse controls, attachment policy, maximum sizes, parser
isolation, injection defenses, and point at which content becomes E2EE. Until
those controls are accepted, email ingestion is not approved for implementation.

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

Email/provider boundaries, AI compatibility, remote push, backup/recovery format,
deletion deadlines, production RP domain/hosting, device-attestation policy, and
metadata retention beyond the seven-day relay rule require approval or Stage 3/4
implementation. Physical-device validation is required before release.
