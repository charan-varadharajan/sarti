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
