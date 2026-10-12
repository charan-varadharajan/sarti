# BUG-003 verification — encrypted child profile synchronization

Date: 2026-10-12. Outcome: child creation/synchronization defect resolved in
Unreleased work. Stage 3 and production release remain unaccepted. BUG-010 is a
separate High-severity replacement-device security blocker discovered in review.

Fix commit: `48d3b44` (`fix(sync): complete encrypted child sharing (closes BUG-003)`).

## Implemented behavior and approval scope

- Add-child UI saves immediately with an atomic SQLCipher profile/outbox/consent
  transaction. Explicit sharing with current calendar guardians defaults off;
  selected sharing grants read access at first server provisioning only.
- Child UUID equals its resource UUID. Names, aliases and colours stay inside
  SQLCipher and independent child-resource ciphertext. Stable provisioning is
  idempotent and rejects resource-family/kind collisions.
- Authenticated bootstrap discovers an existing guardian family without trying
  owner-only creation, then exchanges signed sealed keys before encrypted sync.
  Active/read-authorized recipient checks and active/admin granter checks apply.
- Key acceptance verifies canonical signature, recipient, resource, epoch,
  sealed-box decryption and consistency with any locally held epoch key.
- Current epoch initialization is serialized under the server resource lock;
  racing admins wait for the first established key. Remaining authorized devices
  converge; revoked recipients receive no new child/epoch key.
- Upload retries reuse a persisted exact ciphertext envelope. Rotation during
  a pending upload preserves its operation ID/sequence, acknowledging an exact
  existing receipt or re-encrypting an unaccepted stale operation with the new key. Child/calendar
  resource kinds and decrypted payload scope are checked. Duplicate application,
  reordered event/profile delivery and late permission/key delivery are safe.
- Hidden nameless placeholders preserve event assignments when a separate child
  profile is unreadable or delayed. Conflicting same-ID child creations fail
  closed rather than silently overwriting. This operation does not edit profiles.

Implements accepted ADR-020/021/022; no superseding ADR, external service,
dependency, cryptographic primitive, or approval exception was introduced. New
invitation/approval administration remains BUG-004. No Stage 4 work was started.
Version remains `0.1.0+1`; this is Unreleased remediation, not a public release.

## Changed surfaces

| Area | Files / change |
| --- | --- |
| API | `backend/src/sarti_backend/api/households.py`, `api/sync.py`, generated `backend/openapi.json`; stable child resources/explicit consent, authorized device directory, unique/current signed grants, exact replay and filtered relay paging |
| Local schema | `mobile/lib/src/core/database/sarti_database.dart`; SQLCipher migration v6: exact retry envelope, placeholders, resource catalog, child epoch/consent markers |
| Mobile data/UI | `calendar_repository.dart`, `calendar_controller.dart`, `calendar_screen.dart`; atomic child operation, validated remote apply, explicit sharing checkbox, safe placeholder relationships |
| Mobile transport/runtime | `core/ids.dart`, `core/network/sarti_api.dart`, `resource_key_sync.dart`, `sync_engine.dart`, `authenticated_calendar_bootstrap.dart`; canonical grants, authenticated recipient discovery/import, ordered encrypted delivery |
| Tests | New `child_profile_sync_test.dart`, `child_sync_api_client_test.dart`, `support/child_sync_fixture.dart`, native `integration_test/child_profile_sync_test.dart`, PostgreSQL `test_child_sync_api.py`; migration expectation updated in `calendar_and_sync_test.dart` |
| Documentation | Architecture/child flow/key management/offline protocol, API/OpenAPI, database histories/ER, permission/security models, module catalog, scenario catalogue/test strategy, STATUS, BUGS, CHANGELOG and this report |

PostgreSQL remains at migration `0005`: existing metadata/ciphertext tables and
recipient/epoch uniqueness are sufficient. No plaintext family columns were
introduced. Local v5→v6 is transactional and preserves existing encrypted data.

## Executed checks

| Check / command | Final result |
| --- | --- |
| `make mobile-check` — Dart format, Flutter analyze, unit/widget tests with coverage | PASS: 113 tests; no analyzer issues. Includes 17 new BUG-003 tests (16 profile/security/widget/migration + 1 loopback HTTP transport). |
| PostgreSQL `alembic upgrade head` + full `pytest --cov=sarti_backend --cov-report=term-missing` on isolated `sarti_bug003` | PASS: 23 tests; 89.95% combined statement/branch coverage (85% minimum). Includes one additional API journey with many isolation/consent/grant/replay assertions. |
| PostgreSQL migration regression | PASS: upgrade/downgrade/re-upgrade; schema version 5. No new server migration. |
| `CHILD-MIG-001` | PASS: v5→v6 encrypted file preserves child label/colour, assigned event and pending writes; wrong key rejected and plaintext name absent from database bytes. |
| `CHILD-NATIVE-001` on iPhone 18 Pro / iOS 27.0 simulator | PASS: 1 native UI integration test; Xcode test build succeeded. |
| `CHILD-NATIVE-001` on Android 15 / API 35 emulator | PASS: 1 native UI integration test; Gradle test build succeeded. |
| Shipping entry-point builds: `flutter build apk --debug`, `flutter build ios --simulator --debug --no-codesign` | PASS: Android APK and unsigned iOS simulator Runner.app built from final application source. |
| `make backend-check` — Ruff format/lint, strict Mypy, Bandit | PASS. |
| Generated OpenAPI contract test | PASS; schema regenerated from FastAPI. |
| `pip-audit -r backend/requirements-runtime.lock` | PASS: no known vulnerabilities found. |
| `make version-check`, `make version-test` | PASS: version `0.1.0+1`; 3 version tests. |
| Docker current-source smoke using cached runtime and mounted source/migrations | PASS: `/v1/health/live` → ok; `/v1/health/ready` → ready. Temporary container removed; existing services preserved. Fresh image rebuild not rerun after earlier registry timeout. Isolated `sarti_bug003` PostgreSQL test database dropped after verification. |
| Separate BUG-011 PostgreSQL/AEAD diagnostic | CONFIRMED existing failure: JSONB reorders a multi-author vector, so insertion-ordered AAD fails authentication. No fix claimed; single-author child operations are unaffected. |
| Pinned Gitleaks staged-content scan | PASS: no leaks found. |
| `git diff --check` | PASS. |

The targeted BUG-003 mobile suite and PostgreSQL journey were also run during
implementation. Initial development failures (contract drift, lint and fixture
permissions/device constraints) were corrected before the final passing runs.
Fixtures now model distinct owner/guardian accounts, consistent with one active
phone per adult. They do not rely on two active owner phones.

## Security assertions

- Family B and pending/revoked devices cannot access Family A's child directory,
  keys or private profile. A guardian cannot create resources or administer keys
  without the required permission. Explicit sharing is read only.
- Stable retries cannot broaden sharing to later guardians. Child names supplied
  to the metadata API are rejected. The HTTP client sends only opaque routing,
  sharing intent, public keys and sealed keys.
- Wrong-device sealed-box decryption, modified signatures/wrapped keys, wrong
  recipient/granter/epoch and a different same-epoch key fail safely.
- Existing recipient/epoch grants reject conflicting replacement; malformed
  base64 and oversized epochs are rejected. Concurrent epoch initialization is
  serialized and mobile contenders converge on one key.
- Revoked or no-longer-authorized granters/recipients cannot retrieve future
  grants. New stale-epoch writes are rejected; exact already-accepted retries
  only acknowledge the existing receipt after current authorization. Old copied
  data is not remotely erased.
- Cross-family payloads, invalid child fields, forged child content under a
  calendar key, bad digests and recomputed-digest AEAD tampering cannot overwrite
  profiles. Failure leaves the prior profile/cursor intact.
- An injected outbox failure rolls back both child and operation. Offline edits,
  exact receipt-loss retry, duplicate delivery, event-before-profile delivery,
  a newly granted key replaying an earlier cursor, and interrupted pending uploads
  spanning a key rotation are covered.
- Sensitive fields are absent from the new server schema and metadata requests.
  Existing regression tests cover sanitized logging and opaque push payloads.

## Explicit limits and next work

Native tests execute real SQLCipher/libsodium on each platform, but use two
logical device databases within that platform's test app, fixture authorization
and a controlled relay. They do not demonstrate physical cross-phone/cross-OS
networking, native protected storage, real passkey ceremonies, production TLS,
FCM/APNs or provider delivery. Those remain release acceptance checks.

A device missing an earlier resource-key epoch still fails closed on historical
ciphertext and needs an appropriate encrypted snapshot/recovery path. This fix
does not discard unknown-epoch operations or claim that a current key recreates
old content; new-guardian snapshot/onboarding remains BUG-004.

`BACKUP-XPLAT-002` (Android→iOS backup) remains deliberately NOT RUN per user
instruction. Its earlier addition was committed separately; neither backup
portability scenario was executed as part of BUG-003. Existing -001 historical
results remain in `BACKUP-PORTABILITY.md`.

An existing device-replacement issue was found in unchanged authentication code:
old devices/sessions are revoked but resource epochs remain unchanged, violating
ADR-020 future-content separation if a former phone obtains later ciphertext.
Recorded as **BUG-010 (High)**; no fix is claimed here. It is the recommended
next defect. BUG-011 (Medium) also records a confirmed existing multi-author
AAD-ordering failure after a real PostgreSQL JSONB round trip. Child creation
uses a single-author vector; the controlled relay tests do not establish
real-backend concurrent event editing. Canonical/compatible AAD and its real HTTP
regression remain separate work, alongside BUG-004 guardian onboarding. Obtain
the user's explicit go before beginning the next bug. Stage 3 remains blocked; do not begin Stage 4.
