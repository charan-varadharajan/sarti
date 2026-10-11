# Security model

Status: initial threat model; cryptographic protocol design is pending.

Stage 1 implements sanitized structured logging, UUID-only correlation IDs,
generic external errors, typed tenant-scope infrastructure, dependency/static/
secret checks, SQLCipher engine verification, and PostgreSQL readiness. These are
foundation controls; identity, authorization endpoints, E2EE, key management,
sync, email, backup, and deletion are not implemented.

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

## Key lifecycle requirements

Before cryptographic implementation, a dedicated ADR must specify established
algorithms/libraries, device identity, resource key creation and distribution,
authenticated metadata, nonce rules, rotation, member removal, device
replacement, recovery, backup encryption, deletion, and versioning. No security
claim may exceed what the implemented protocol and platform storage provide.

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

The cryptographic protocol, passkey library, platform key-storage integration,
email provider, push provider integration, backup format, deletion deadlines, and
metadata retention schedule require design and review.
