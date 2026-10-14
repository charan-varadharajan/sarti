# ADR-038 — Adult/pet appointment verification

Date: 2026-10-13. Version: 0.2.0+2. All executed final checks pass. Physical/provider gaps and BUG-022 remain.

## Scope and approvals

Maintainer requested adult appointments, explicit household sharing, pets and
pastel profile choices. The maintainer explicitly approved ADR-038 on 2026-10-13
before implementation. It supersedes owner-wide private-resource access and
extends personal recovery under ADR-032. Stage 4 is not started. No new service,
dependency, cloud inference, secrets or production/billing activation.

## Features and changed modules

- Calendar event model: typed adult/pet participants with legacy child support.
- Repository/controller: author-bound resources, atomic independent shared copies,
  no silent overwrite on shared changes, explicit exact-vector review, account
  switching filters, unpublished offline draft binding and durable child colours.
- Presentation: private/shared audience labels, editable own adult/pet profiles,
  six named pastels and deliberate existing-child colour changes. Existing
  colours survive upgrade; names/type labels accompany colours.
- Sync/key module: separate personal/profile resource dispatch and normal
  libsodium epoch/grant/replay rules; personal keys never granted to spouses.
- Backend auth: private_adult_id checked before owner bypass; resource/device/
  grant/list/relay/invitation/replacement routes enforce scope.
- Backup: separate adult-scoped relay, versioned encrypted scope marker,
  wrong-adult rejection and interruption-safe activation. Own personal recovery
  retains historical keys/vectors/applied IDs but never device identity/session/
  outbox envelopes/sequences. Family snapshots sanitize private state and compact
  deleted pages; each snapshot uses an independent fresh SQLCipher key.
- Test runner: `./test --ios --scenario adult` or Android equivalent; `all`
  includes the ten prepared scenarios. No cross-platform backup direction runs.

## APIs, migrations and docs

POST family resources accepts personal_calendar and participant_profile. Personal
backup PUT/GET/DELETE uses the current adult's scope, opaque v2 binary body,
revision CAS, 10-MiB bound and no-store response. OpenAPI regenerated from FastAPI.
PostgreSQL 0008 adds ownership/kind/unique binding, bounded scoped backups and
purge triggers; refuses unsafe downgrade. Local SQLCipher v7 adds private bindings,
profiles, assignments, share mappings and durable child vectors without changing
prior colours/events/envelopes. Existing migration fixtures now remove synthetic
v7/v8 extension tables/rows before exercising older migration guards.
Architecture, key management, security/permission matrix, API/backup docs, both
schemas/ER diagrams, migration history, offline sync, product flow, module catalog,
stable scenarios, status, bugs and changelog updated in the same change.
ADR-030 minor bump reflects the private-beta schema/authorization extension;
no public release tag or publication.

## Tests added and maintained

ADULT-PRIVATE/SHARE/CONFLICT/UI/DRAFT/RECOVERY-001, ADULT-RECOVERY-002,
PROFILE-COLOUR-001, PROFILE-CHILD-001, PET-CAL-001, ADULT-API-001 and ADULT-HTTP-001. Prepared
independent SQLCipher/libsodium devices enter target screens directly. UI creates
prerequisites only when creation itself is the scenario. Real PostgreSQL tests
cover owner/guardian/stranger access, grant recipient denial, replay, scoped
backups, replacement epochs, stale revisions, inactive devices and backup purge.
Existing child rotation preserves identical concurrent snapshots through causal
merge; differing edits remain protected. Migration tests preserve encrypted data.
BUG-020 failure drivers settle pending rebuilds before Add, scroll to the actual
child checkbox and assert selected colour rather than the removed fixed default.
No assertion is dropped to obtain a pass.

## Final executed checks

| Check | Result |
| --- | --- |
| Flutter full unit/widget/security/transport suite | PASS: 169; 2 opt-in HTTP cases skipped here and executed through backend hosts; adr038-flutter-final.log |
| Focused final backup/private recovery | PASS: 16; adr038-backup-final.log |
| Dart formatting / Flutter analysis | PASS; adr038-format-final.log / adr038-analyze-final.log |
| iOS simulator prepared journeys | PASS: 19 distinct scenarios across 18-case base run, final 9-case adult rerun and added child-colour case |
| Android emulator same journeys | PASS: same 19 distinct scenarios and final recovery/colour reruns |
| Backend/PostgreSQL including enabled real HTTP/Dart contracts | PASS: 31, no skips; 91.52% coverage; adr038-backend-full.log |
| PostgreSQL migration | PASS: upgrade, guarded downgrade/re-upgrade and ciphertext preservation |
| Backend format/Ruff/Mypy/Bandit | PASS |
| Generated OpenAPI contract | PASS in complete backend suite |
| Version integrity / script tests | PASS: 0.2.0+2 / 8 tests |
| Pinned runtime dependency audit | PASS: no known vulnerabilities |
| Docker build/start/readiness | PASS: current local backend/schema; live and ready HTTP 200 |
| Staged offline secret scan / whitespace | PASS; pinned cached Gitleaks, no network/mounts; staged diff clean |

Ignored logs are under test-results/adr038-*. Only failed-case diagnostics were
inspected, under the maintainer's explicit test/fix/rerun instruction.

## Security findings and limits

Resolved in this scope: owner bypass for private data, snapshot/live-store key
reuse risk, private rows/keys in family exports/handoffs,
shared-copy overwrite without review, and private restore losing causal state.
The family-only ADR-032 continuation remains BUG-022, newly recorded from code
inspection; its full resumed-sync/device reproduction is not claimed. Other
open BUG-005/012/013/014/017/021 and production deletion/provider gaps remain.

No physical phone, real passkey, Keychain/Keystore, camera/link/share extension,
actual APNs/FCM/email provider, on-device AI compatibility or production load/cost
acceptance is inferred from these tests. Controlled directory/relay tests and
real HTTP/PostgreSQL contracts use synthetic users and stub WebAuthn verification.
Same-platform recovery executes real encryption/SQLCipher; neither cross-platform
backup portability direction is rerun, and Android-to-iOS remains explicitly
unrun. No P0/Stage-3 release-ready claim. Recommend maintainer device acceptance
and a separate BUG-022 recovery decision; do not start another stage automatically.

## Native execution detail

Base runs: adr038-ios.log / adr038-android.log (18 each). After fresh snapshot
keys and final audience labels: adr038-ios-final.log / adr038-android-final.log
(9 each). Explicit legacy-child correction: adr038-ios-child-colour.log /
adr038-android-child-colour.log (1 each). Simulator: iPhone 18 Pro, iOS 27,
A351256A-6255-4285-A1AE-5624594A08FD; Android API 35, emulator-5554.
Current grid/guardian native suites were not rerun; their unit regressions and
real HTTP guardian contract pass. CI itself was not observed for this push.
User local iOS signing edits are excluded. No physical deployment is claimed.

Implementation commit: `12a3c210d95da75e016b1b7aa474390a329003bf`. Verification-only follow-up records this
identity without changing implementation or test results.
