# Project status

- Current stage: Stage 3 — AI proposals, email intake, push notifications, and backup/recovery
- Updated: 2026-10-13
- Stage state: remediation in progress; BUG-001/002/003/004 remediation delivered; provider/device validation and BUG-005 live provider acceptance deferred; physical/provider validation outstanding
- Repository version: `0.5.0+5`; no public release tag

## Current result

Combined remediation for BUG-012/013/014/017/021 implemented and verified;
BUG-005 credential/broker code is implemented disabled by default under approved
ADR-037, with live provider acceptance explicitly deferred by maintainer.
Native on-device AI remains primary, with local deterministic fallback; Gemini
is optional. PostgreSQL 0010 adds usage metadata only; local schema remains v9.
Final checks: Flutter 212 pass/2 HTTP opt-in skips (both hosts executed), backend
57 pass/91.25% coverage, native iOS 69 distinct checks and Android 10 combined/
DST checks. Both normal builds and required static/audit/tooling/migration/health/
secret gates pass. See testing/REMAINING-BUGS-VERIFICATION.md for exact evidence
and limits. Remote CI is not inferred from local checks. No Stage 4,
billing, production deployment or real-family cloud request. Local signing edits
remain excluded. Older results below are historical baselines.


ADR-040 is maintainer-approved and implemented in development 0.4.0+4.
Family recovery preserves scoped history and unsent intent while resetting former
credential/envelope bindings. Fresh authority/current keys, download-only catch-up
and explicit review gate publication; cleanup needs separate history review.
Local schema v9; PostgreSQL stays 0009 and backup envelope stays v2. BUG-022 is
resolved: Flutter 202 pass/2 opt-in skips (both HTTP hosts executed), backend
33 pass/91.51% coverage, native recovery 15 pass each on iOS/Android. Required
static/audit/migration/tooling/version/Docker/health/secret gates pass. See
testing/BUG-022-VERIFICATION.md for physical/provider/legacy/TTL limits. No next
bug or stage started. Local signing edits remain outside this change.

ADR-039 was explicitly approved and is implemented and verified in
0.3.0+3: one admin-managed family calendar retention policy, default one week,
with one/three months, one year and Never. Future appointments/active series stay.
New server families adopt the default; legacy families require admin adoption.
PostgreSQL 0009/local SQLCipher v8 add bounded policy metadata and minimized
causal deletion/conflict records. Server relay/backup TTLs remain unchanged.
Family-only restore cleanup pauses until ADR-040 review succeeds; incomplete
legacy history stays blocked. Offline-only builds need configured service/auth before managing the family
policy or initiating cleanup. Final checks pass: Flutter 184 pass/2 opt-in skips (both executed via HTTP hosts),
backend 33 pass at 91.51%, native retention 12 pass each on iOS/Android; static,
audit, tooling, version, Docker/health and secret scan pass. Full details and
physical/recovery limitations: testing/ADR-039-VERIFICATION.md.


ADR-038 adult/pet extension is implemented and passes all executed final checks:
private-by-default adult resources, explicit household copies, pastel profiles,
pets, own encrypted backups and safe private recovery. Flutter 169 pass/2 opt-in
skips; backend including both enabled HTTP/Dart contracts 31 pass at 91.52%;
iOS/Android 19 distinct prepared scenarios each. Analysis, format, security,
version, audit and current Docker/health gates pass. See
`testing/ADR-038-VERIFICATION.md`. BUG-022 records the separate family-only
recovery continuation gap. Physical/provider acceptance remains pending;
Stage 3 is not declared release-ready.


BUG-020 setup and BUG-015 colours are resolved for automated scope. The final
Flutter suite passes 169 cases (2 opt-in skips executed through the separate
HTTP hosts); both native platforms pass the prepared family/calendar/child/adult
journeys and explicit old-child colour correction. Physical acceptance remains.
See `testing/BUG-020-VERIFICATION.md` and `testing/ADR-038-VERIFICATION.md`.


ADR-038 was explicitly approved and is implemented; final verification is
recorded above. No Stage 4 work or production deployment is authorized by this change.


BUG-018 Today navigation is resolved for automated scope:
repeatable day-mode action, current date in the configured display timezone,
retained agenda state and unchanged week/month toolbar behavior. Seven prepared
regressions are shared by widget/native grid suites. Analysis, full Flutter suite
(151 pass, 2 opt-in skips) and iOS/Android native suites (10 each) PASS. Physical
iPhone rebuild/retest remains pending. No server/database/crypto/dependency
change; local signing edits remain untouched. See `testing/BUG-018-VERIFICATION.md`.


Physical-iPhone testing reported Today navigation (BUG-018), first-family hidden
creation controls (BUG-019), missing optional guided setup (BUG-020) and no
unified family-management hub (BUG-021). BUG-019 is prioritized in isolation:
bootstrap presentation now observes controller changes and reevaluates existing
permission checks immediately after family creation. Analysis and full Flutter
suite PASS (144 passed, 2 opt-in skips), including prepared owner/read-only/revoked
regressions. BUG-019 is resolved for automated scope; physical retest is pending.
See `testing/BUG-019-VERIFICATION.md`. Other reports remain pending, with child colour
selection linked to existing BUG-015. Local Xcode signing changes are preserved.


Remaining BUG-005 integration has a reviewable proposal in
`architecture/adr/037-server-managed-cloud-assist.md`: disabled billing-backed
broker, explicitly disclosed Sarti processing, server-only credentials and
atomic usage caps. Provider terms prohibit sensitive/personal input to unpaid
services; paid processing still has retention limits requiring disclosure.
ADR-037 is proposed, not accepted. No runtime/API/schema change or billing
activation was made during this design review.


BUG-005 privacy controls are tightened under approved ADR-036: fresh per-request
labels, no model-payload requester IDs, bounded supported-token submission,
source-grounded output and renewed consent. Privacy/UI/public-copy guidance
separates encrypted sync/backup, native AI, optional cloud disclosure and email
plaintext processing. Cloud credential/shipping integration and live provider
validation remain open; no cloud service is activated by this change. Analysis,
full Flutter suite (140 pass, 2 opt-in skips), final privacy/consent tests, backend
unit/static/dependency checks and existing local service health pass. Results:
`testing/BUG-005-PRIVACY-VERIFICATION.md`.


BUG-004 guardian onboarding is implemented under ADR-035: share/copy/QR,
acceptance, verified owner approval, scoped initial encryption and read-only UI.
Migration 0007 adds relay baselines. Backend/migration/security, dependency,
tooling, Docker health and shipping iOS/Android builds pass. After authorized
failure investigation, the profile-apply transaction, fixture initialization and
QR assertions were corrected. Analysis, full Flutter suite, real HTTP guardian
test and both prepared native guardian suites pass (3 scenarios each). BUG-004
is resolved for implemented and automated scope. See `testing/BUG-004-VERIFICATION.md`.
Physical camera/share/link/passkey behavior requires separate validation.


BUG-011 is resolved under approved ADR-034, with migration 0006 and legacy
ciphertext preservation. Full backend/PostgreSQL and Flutter suites, the real
HTTP/PostgreSQL/Dart regression, static/security/dependency checks, Docker
startup/health, offline secret scan, OpenAPI and version checks all pass on
2026-10-13. See `testing/BUG-011-VERIFICATION.md` for evidence and limits.
BUG-017 remote conflict-card retirement remains open separately; no other
behavior was fixed during closure.

BUG-010 is resolved. Full PostgreSQL/backend and Flutter regression suites,
migrations, static/security/dependency checks, offline pinned secret scan,
OpenAPI drift and version integrity all pass on the corrected source. See
`testing/BUG-010-VERIFICATION.md` for commands and remaining physical-device
release checks. No other defect was changed.

BUG-016 Kalender 0.33.0 presentation integration is resolved under ADR-033.
Two incorrect test expectations were corrected; application behavior did not
change in the follow-up. Full Flutter regression tests pass (120/120), as do
prepared grid tests on iOS (3/3) and Android (3/3), formatting and static analysis.
See `testing/BUG-016-VERIFICATION.md` for results and device/accessibility limits.
This does not close BUG-013/014/015 or the existing security/release blockers.

The software-only privacy remediation now connects the shipping mobile app to
authenticated API sessions, encrypted synchronization, opaque push lifecycle,
and device-addressed encrypted email suggestions. The backend no longer stores
email sender, subject, or body in plaintext. Migration `0004` replaces those
columns with libsodium sealed-box ciphertext addressed separately to each active
device. Mobile decrypts locally, identifies the external sender, and requires the
normal editable proposal and explicit save action.

Stage 3 is not accepted yet. Approved ADR-031 fixes BIP-39 phrase generation;
approved ADR-032 fixes the replacement-device SQLCipher key envelope and adds
an owner-only encrypted backup relay. Explicit upload, automatic download after
login, phrase confirmation, validated staging, and protected-key activation are
implemented and tested. Login alone does not decrypt a backup. Physical two-phone
recovery, future resource-key grants (BUG-004), and the other open defects below
remain acceptance gaps. No Stage 4 work is authorized.

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
- BIP-39 recovery phrases, v2 recoverable SQLCipher-key envelope, owner-only
  encrypted snapshot upload/download/delete, replacement-phone recovery UI,
  staged integrity/family/schema validation, and interruption-safe protected-key
  activation. Migration `0005` stores one bounded opaque snapshot per family.
  Old identity credentials and sync keys are not restored.
- BUG-003: atomic offline child creation, stable child resources, explicit
  read-only sharing consent, signed sealed-key delivery, epoch convergence,
  validated profile sync and receiving-calendar labels/colours. Prepared native
  child-sync scenarios pass on iOS and Android; SQLCipher schema is now v6.
- Repository-wide SemVer/build numbering policy, drift checker, bump command,
  tests, CI tag validation, and release documentation under ADR-030.
- Stable functional-scenario IDs, reusable synthetic Flutter fixtures, direct
  target-flow entry helpers, and automatic database teardown. `CAL-MOB-001`
  runs from a prepared calendar on widget tests and an Android emulator.

## Latest local verification

| Check | Result |
| --- | --- |
| Backend Pytest unit + PostgreSQL integration | PASS on 2026-10-13; 31 tests including enabled HTTP/Dart contracts, coverage 91.52%; ADR-038 report |
| Alembic upgrade to head | PASS on 2026-10-13; PostgreSQL 0009; SQLCipher v9; BUG-022 report |
| Ruff / strict Mypy / Bandit | Passed |
| OpenAPI contract | Passed |
| Docker current-source smoke | Passed using cached runtime + current source/migrations; clean rebuild not rerun after prior Docker Hub timeout |
| Flutter format / analyze | Passed; no issues |
| Flutter unit/widget tests | PASS on 2026-10-13; 169 passed, 2 host-dependent skips separately executed; ADR-038 report |
| Native child sync | `CHILD-NATIVE-001` passed on Android API 35 and iPhone 18 Pro / iOS 27.0; controlled relay and two logical guardian devices |
| Prepared mobile emulator scenario | `CAL-MOB-001` passed on Android API 35 and iPhone 18 Pro / iOS 27.0 on 2026-10-12 |
| Cross-platform encrypted backup | `BACKUP-XPLAT-001` passed: iPhone 18 Pro / iOS 27.0 simulator exports real `.srtbk`; Android 15 / API 35 emulator restores identical ciphertext; physical devices, auth/relay and protected storage excluded |
| Android debug / unsigned iOS simulator debug builds | Passed; APK and Runner.app produced |
| Pip-audit runtime dependency scan | Passed; no known vulnerabilities |
| Version checker/tests | Passed; 3 tests |

`BACKUP-XPLAT-002` (Android-to-iOS) is added but deliberately not run at the
user's request. The shared directional runner has static validation only since
that addition; the existing -001 result above refers to its prior executed revision.

Pinned Gitleaks Docker scan passed with no leaks. OpenAPI was regenerated from
the app and its contract test passes. Native build results are recorded in the
BUG-002 and BUG-003 verification reports; provider/device results are not inferred.

## Remaining Stage 2 and Stage 3 work

- BUG-017 resolved in 0.5.0+5; remaining work is release/provider/device acceptance.
- Guardian invitation/approval and scoped initial state are implemented and
  automated checks pass. Physical camera/share/link/passkey/provider validation
  remains; do not infer it from fixtures or local HTTP contracts.
- Run the shipping backup journey on physical replacement phones, including
  platform protected storage and interruption/retry. Automated SQLCipher/API/UI
  coverage is complete for BUG-002; fresh future sync grants remain BUG-004.
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
