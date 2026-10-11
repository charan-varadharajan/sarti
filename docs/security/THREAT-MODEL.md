# Threat model

| Threat | Stage 1 control | Required verification |
| --- | --- | --- |
| Family-to-family leakage | Fail-closed typed tenant context | Two-family negative API/repository tests for every resource |
| Unauthorized guardian | Authentication, active-device, role, resource checks required | Missing/incorrect role and guessed-ID tests |
| Lost/stolen device | Biometrics locally; backend device revocation | Locked-device and post-revocation access tests on real devices |
| Compromised credentials | Passkey design plus active-device policy required | Session replay, recovery, replacement, and revocation tests |
| Key rotation/recovery failure | Protocol explicitly blocked pending ADR | Rotation, removed-member, backup and corrupt-recovery tests |
| Malicious sync payload | Authenticated ciphertext and strict bounds required | Tamper, size, schema, duplicate, order, rollback, replay tests |
| Email prompt injection | Email treated as hostile; no automatic mutation | Injection corpus and explicit-confirmation tests |
| Sensitive logging | Allowlisted JSON operational fields | Capture logs during hostile inputs and scan for canaries |
| Backup exposure | Device-side encryption and user-held recovery required | Wrong-key, corruption, metadata and provider-exposure tests |
| Replay attacks | Protocol must authenticate ordering/nonces | Replayed auth and sync message tests |
| Account/family deletion | User control and deletion orchestration required | Idempotency, partial failure, retention and completion tests |

## Residual risks

An unlocked compromised authorized device can expose data it already holds.
Revocation cannot erase downloaded copies. Email is plaintext during its declared
gateway boundary. Metadata may reveal limited relationships or timing and must be
classified and minimized before those schemas are introduced.

Stage 1 does not implement passkeys, E2EE, sync, email, backup, export, deletion,
or product authorization. Its SQLCipher engine check establishes encrypted-store
capability only and is not evidence that family data or E2EE exists.
