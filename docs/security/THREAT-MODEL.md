# Threat model

| Threat | Implemented Stage 2 control | Verification / residual gap |
| --- | --- | --- |
| Family-to-family leakage | Session, active-device, membership, resource permission, and family-scoped query checks | Two-family integration test, including an empty relay |
| Unauthorized guardian | One-use hashed invite, pending membership, owner approval, explicit permission matrix | Duplicate invite, outsider, pending, revoked-recipient tests; invitation delivery channel remains external |
| Lost/stolen device | Platform user-presence gate, one active phone, replacement revokes old sessions | API replacement test; physical locked-device validation pending |
| Compromised credential | Required WebAuthn user verification, one-use challenge, hashed expiring session | Auth replay and old-session tests; account recovery is Stage 3 |
| Key rotation/recovery failure | Removal increments all resource epochs; future grants exclude revoked device | Stale epoch and revoked grant tests; v2 key-envelope and protected-key retry tests; physical recovery pending |
| Malicious sync payload | Bounded schemas, exact sequence, UUID/digest/epoch checks, AEAD tag, durable de-duplication | Malformed digest, duplicate, replay, no-key, and conflict tests |
| Email prompt injection | Sanitization, bounded input, per-device sealed delivery, on-device parsing, explicit approval | Injection, ciphertext isolation/tamper, and no-preapproval-write tests; live Cloudflare test pending |
| Sensitive logging | Allowlisted fields, generic errors, no body/ciphertext/token logging | Canary log test and Bandit/Gitleaks gates |
| Backup exposure | Independent PBKDF2/XChaCha20-Poly1305 envelope with validated BIP-39 recovery phrase; corruption and wrong phrase fail closed | BIP-39 vector and envelope tests pass; v2 SQLCipher key recovery, owner/tenant isolation, revision conflict and deletion tests pass; physical restore pending |
| Replay attacks | One-use WebAuthn challenge, operation UUID, exact device sequence | Authentication and sync replay tests |
| Account/family deletion | Not implemented | Stage 4 deletion deadlines, idempotency, partial-failure tests required |

An unlocked compromised authorized device can expose content and keys it already
holds. Revocation protects only future content and cannot remotely erase copies.
The server observes bounded relationship/timing metadata and ciphertext sizes.
Physical OS behavior, production TLS/RP configuration, snapshot recovery after
seven offline days, live email/provider delivery, backup recovery, and deletion
remain residual risks.

## Guardian onboarding (ADR-035 / BUG-004)

Forwarded/stolen invitation links can create pending requests but cannot grant
content access: expiry/single use, owner recognition, matching out-of-band device
code, full key/device pinning and signed scoped grants gate approval. Unknown
schemes/hosts/paths/query-bearing links are rejected; a QR cannot override
permissions or API routing. Tokens are not sent to API URLs or operational logs.
Owner-selected messaging/clipboard apps necessarily receive the expiring token;
no family details or encryption keys are included. Pending/revoked, foreign-family,
changed-device, duplicate/expired/cancelled and expanded-permission requests need
negative tests. Initial state must respect child-resource isolation, retries,
retained data, existing conflicts and current key epochs. See GUARD-* scenarios.

## Optional cloud disclosure — ADR-036

Stable alias correlation is reduced with fresh per-request labels and omission
of requester IDs from the model payload. Raw sentences and unsupported text are
blocked by a bounded token grammar; captured-transport tests prove no call for
synthetic names/addresses/email/phone/medical/injection cases. Scheduling tokens,
recognized common words and provider/network metadata may still be identifying.
Consent v2, truthful copy and strict source-supported response validation reduce
accidental disclosure and invented changes; they do not establish anonymity,
general PII detection, provider retention/training or production eligibility.

## Restored-history continuation (ADR-040 / BUG-022)

Threats: erased old keys block relay; erased vectors permit silent overwrite;
reused outbox binds mutations to a revoked device; cached access/profile consent
resurrects resources or broadens sharing; cleanup deletes unreviewed restored
history. Controls: scope-validated encrypted historical keys/vectors/applied IDs,
quarantined intent, fresh current authorization/key epoch, download-only catch-up,
exact reviewed family/resource/kind/payload/vector binding, atomic new operation
and durable retry, explicit conflicts/profile-sharing/retention review.

Test mapping: CONT-001/002 historical decryption/concurrency; CONT-003/003A/005B
retry/create/delete/replacement; CONT-004 and KEY/SCOPE current authority/private/
tenant denial; CONT-005A malformed AEAD/cursor; GATE-001 unreviewed publication;
CONT-006/006A cleanup approval and stale policy; CONT-007 fresh sharing choice;
HTTP host validates real server replacement/revocation/grants. Relay expiry is a
disclosed unavailable-history risk, not proof of latest completeness. Physical
secure storage/passkeys/interruption and production provider behavior remain
release checks. Existing backend authorization/replay/security suites still apply.

Calendar retention also removes completed recovery-intent bodies for the deleted
entry; unresolved/quarantined intent and exact pending retries are protected.
RECOVERY-RETENTION-001 verifies this minimization boundary.

## Optional broker and remaining-bug controls (ADR-037)

Threats: embedded mobile credentials, silent cloud fallback, token injection,
provider redirects/logging, replay-driven spend, stale conflict/data overwrite
and unintended Undo deletion. Controls: runtime-only server secret, explicit
v3 consent/action, fail-closed grammar/extra fields, fixed host/no redirects,
bounded response/total deadline/no retry, atomic adult/global attempt caps,
safe content-free logs and independent phone evidence checks. Calls remain
separate from sync E2EE. Provider eligibility/retention/live acceptance are
deferred activation gates; pseudonyms are not anonymous.

Tests: CLOUD-BROKER/QUOTA/API/MOB schema, captured transport, revoked device,
concurrent quotas, expiry/account purge; CONFLICT-RETIRE and AAD-HTTP causal
retirement/stale rejection; NLP-BATCH-SEC atomic cross-family rollback;
UNDO-MOB dirty/reverted/cancel/expiry plus existing explicit Delete journey;
FAMILY-HUB encrypted peer update and guardian/foreign-write denial.


## Stage 5 scoped-membership threats — ADR-041 foundation

| Threat | Current foundation control / evidence | Remaining acceptance |
| --- | --- | --- |
| Scoped admin escalates child access through old invite/backup paths | BUG-024/025 explicit resource checks; ordinary re-entry clears revoked admin role; test_context_administration.py | Operation-bound legacy mutation UI/audit integration |
| Simultaneous final-admin demotions | Context/ordered adult-resource locks; real PostgreSQL concurrent self-demotions leave one administrator | Closure/transfer/account deletion journey |
| Stolen session replays or changes sensitive intent | Current-phone WebAuthn; five-minute hashed single-use scoped proof, current session/device/ACL; test_sensitive_step_up.py | Physical ceremonies and all sensitive routes |
| Caregiver receives broad family keys | New role/grant API denies household profile/calendar/audit and write grants; expiry rotates lost grants | Reviewed independent ciphertext copies and shipping caregiver UX |
| Household switch corrupts/reveals another scope | Pinned SQLCipher queries/private/recovery state, global upload serialization and exact interrupted retry; multi_household_state_test.dart | Shipping selector/runtime/enrollment and stale editor acceptance |
| Multi-household backup exposes unrelated keys | Encrypted-copy sanitization; real snapshot restore inspection and wrong-key/migration tests | Occupied-store scoped import and complete export step-up |
| Client supplies misleading audit narration | Ciphertext kept separate from authoritative action/target/outcome/revision; atomic DB transaction and AEAD fixture | Client viewer must verify narration against outcome metadata |
| Downgrade restores implicit legacy owner power | Migration 0012 refuses scoped-admin escalation; actual guarded Alembic rollback fixture | Coordinated beta client/backend rollout |
| Recovery or deletion resurrects expired content | Existing hard retention and current-authority recovery gate preserved | Stage 5 manual trash/restore and closure/purge remain unimplemented |

No permanent server decryption key, new cloud fallback or service was introduced.
Old downloaded content, external backups and physical/provider acceptance remain
outside the automated component-test guarantee. These controls do not establish
full Stage 5 completion; see ../STAGE-5-REPORT.md.


Stage 5 unavailable-context denial of service / BUG-026: exact uncertain upload
may occupy a device sequence after resource revocation. Explicit own-device
receipt review under current auth and resource/device locks, bounded metadata-only
response, stale-review rejection and encrypted local quarantine allow independent
contexts to resume without replay or silently abandoning work. Expired receipts
cannot establish delivery; original content remains preserved for later review.
