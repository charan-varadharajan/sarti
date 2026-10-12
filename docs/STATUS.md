# Project status

- Current stage: Stage 3 — AI proposals, email intake, push notifications, and backup/recovery
- Updated: 2026-10-12
- Stage state: remediation in progress; recovery design approval and provider/device validation outstanding
- Repository version: `0.1.0+1`; no public release tag

## Current result

The software-only privacy remediation now connects the shipping mobile app to
authenticated API sessions, encrypted synchronization, opaque push lifecycle,
and device-addressed encrypted email suggestions. The backend no longer stores
email sender, subject, or body in plaintext. Migration `0004` replaces those
columns with libsodium sealed-box ciphertext addressed separately to each active
device. Mobile decrypts locally, identifies the external sender, and requires the
normal editable proposal and explicit save action.

Stage 3 is not accepted yet. Two defects in the accepted recovery design require
a superseding ADR before safe implementation:

- the implemented 12-word phrase selects from a 256-word subset and has no
  BIP-39 checksum, so it is not the BIP-39 mnemonic required by ADR-025; and
- ADR-025 encrypts raw SQLCipher database bytes with an independent backup key,
  but a replacement device does not possess the SQLCipher key needed to open the
  restored file. The ADR explicitly excludes device secrets and does not define
  a recoverable database-key envelope or logical export.

The applicable stop conditions are an accepted-ADR change, a security guarantee
that cannot presently be met, a material dependency choice for BIP-39, and a
failed architecture assumption. No backup UI or release claim will be built on
the flawed format.

## Delivered

### Stages 1 and 2

- Flutter/Riverpod and FastAPI/PostgreSQL foundation, Docker development,
  migrations, CI quality gates, structured errors, sanitized logs, and health
  endpoints.
- Passkey API, one-active-phone authorization, households, guardian invitation
  and permission primitives, SQLCipher local storage, resource cryptography,
  encrypted relay, replay protection, offline outbox, explicit conflicts,
  calendar views, recurrence/DST behavior, pickup assignment, and local reminders.

### Stage 3

- Deterministic natural-language parser and native Apple Foundation Models /
  Android ML Kit bridges with runtime gates, local fallback, editable proposals,
  explicit confirmation, and Undo.
- Optional Gemini adapter behind versioned opt-in and local child/location
  pseudonymization. Production provider terms and credentials remain unverified.
- Cloudflare email ingress controls: worker secret, bounded input, injection
  sanitization, hashed routing token, rate limit, deduplication, and seven-day
  expiry.
- Per-device PyNaCl/libsodium sealed-box email encryption, authenticated polling
  and dismissal, local decryption, source attribution, proposal review, and
  post-approval dismissal.
- Authenticated mobile bootstrap with secure session persistence, stable offline
  family provisioning, serialized encrypted sync, wake-up dispatch after upload,
  email refresh, session expiry handling, and foreground catch-up.
- Opaque FCM payload validation and token rotation. ADR-026 deliberately uses OS
  notification controls for quiet hours; no sensitive schedule content is sent.
- Backup envelope cryptography and corruption/wrong-key tests exist, but the
  recovery format is non-conforming and unusable for replacement-device restore
  until the design issues above are approved and fixed.
- Repository-wide SemVer/build numbering policy, drift checker, bump command,
  tests, CI tag validation, and release documentation under ADR-030.
- Stable functional-scenario IDs, reusable synthetic Flutter fixtures, direct
  target-flow entry helpers, and automatic database teardown. `CAL-MOB-001`
  runs from a prepared calendar on widget tests and an Android emulator.

## Latest local verification

| Check | Result |
| --- | --- |
| Backend Pytest unit + PostgreSQL integration | 21 passed; 87.17% branch coverage |
| Alembic upgrade to head | Passed; schema version 4 |
| Ruff / strict Mypy / Bandit | Passed |
| OpenAPI contract | Passed |
| Docker Compose health | Backend and PostgreSQL healthy |
| Flutter format / analyze | Passed; no issues |
| Flutter unit/widget tests | 80 passed on 2026-10-12 |
| Prepared mobile emulator scenario | `CAL-MOB-001` passed on Android API 35 and iPhone 18 Pro / iOS 27.0 on 2026-10-12 |
| Android debug / unsigned iOS debug builds | Passed; APK and Runner.app produced |
| Pip-audit runtime dependency scan | Passed; no known vulnerabilities |
| Version checker/tests | Passed; 3 tests |

Gitleaks was not installed for this local rerun; it remains a CI gate. Final
OpenAPI drift is checked before the remediation commit.

## Remaining Stage 2 and Stage 3 work

- Child profile creation is still local-only. The server has a child-resource
  endpoint, but mobile does not provision that resource, encrypt the profile, or
  distribute its key. Cross-device child labels therefore remain incomplete.
- Guardian invitation/approval and resource-key delivery exist in backend and
  protocol tests but are not connected to a complete shipping mobile journey.
- Approve a superseding recovery ADR and implement a true BIP-39 phrase plus a
  replacement-device-restorable payload.
- Run physical iOS/Android tests for passkeys, secure storage, local reminders,
  native AI, FCM/APNs, background/foreground behavior, and two-device sync.
- Run live Cloudflare email routing and approved Gemini provider tests with
  production-equivalent configuration.

## Hosting

ADR-027 selects Google Cloud Run plus Neon Free for development and the initial
private beta. Production hosting remains unresolved until Stage 3 recovery and
provider/device validation pass.

Do not begin Stage 4 until Stage 3 is accepted and the user explicitly approves
the next stage.
