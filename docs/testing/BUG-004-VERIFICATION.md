# BUG-004 — Guardian invitations, QR and scoped handoff verification

Date: 2026-10-13. Status: **Resolved for implemented/automated scope; physical/provider validation remains.**

## Approval and scope

The maintainer approved the guardian invitation/approval/key-delivery work,
share sheet/copy link, and explicitly requested QR in this fix. ADR-035 records
implementation decisions within that scope; existing ADR-019/020/022/034
semantics are preserved. No Stage 4 work or external messaging service added.
The standing instruction is to run tests, save logs, and report pass/fail without
failure diagnosis or automatic retry. That instruction was followed.

## Implementation and changed areas

- `features/guardians/invitation_links.dart`: strict bounded token/custom-scheme
  parser and memory-only cold/warm inbox, started before device unlock in main.
  Links cannot change API routing or permissions; tokens never become API URLs.
- `guardian_screen.dart`: native share sheet, copy link, offline local QR,
  acceptance/waiting state, matching public-device code, local guardian name,
  calendar read/write and selected child-profile review, cancellation, explicit
  interrupted-sharing retry and confirmed guardian removal.
- `guardian_coordinator.dart`: one-local-family attachment, SQLCipher cached
  access/readiness, server device/key pins, same-permission retry and key/state
  handoff coordination. The native system camera/QR reader opens an installed
  app; no in-app scanner, contacts, inbox or message-read permission is added.
- Authenticated bootstrap wires links and membership refresh into the existing
  runtime. Calendar views allow read-only details while disabling mutation and
  child creation for restricted guardians. Existing owner calendar behavior,
  Undo, parsing and colour defects were not otherwise changed.
- Calendar repository queues current selected children, unchanged events and
  tombstones, then encrypted family/guardian profiles. It validates resource,
  identity, bounds and profile causality before marking handoff ready. Progress
  references queued IDs; explicit retries can recover orphaned progress after
  old-identity outbox clearing. Open event conflicts block initial handoff rather
  than dropping alternatives.
- Resource-key synchronization includes family-profile keys using the existing
  first-granter signed sealed-box protocol, without replacing established keys.
- Backend household APIs add bounded owner review/cancellation, recipient-device/
  public-key pins, resource subsets, exact approval retries, expired/cancelled/
  removed re-enrollment and serialized invitation quotas. Family/adult/resource
  locks are consistent with replacement; active actor checks guard transitions.
  Removal retires stale invitations and rotates existing resource epochs.
- Migration `0007` adds nonnegative default-zero `memberships.sync_start_cursor`.
  Approval captures a baseline; downloads enforce it even after client cursor
  reset. Pending lists expose no resources, active guardian lists only permitted
  ones. No plaintext private profile or key is added. Downgrade refuses nonzero
  baselines. Destructive tests reset only synthetic baseline metadata.
- Native scheme registrations added to Android manifest/iOS plist; framework URL
  routing disabled so bearer links are handled by the strict invitation inbox.
- Pinned packages/lock: share_plus 13.3.1, app_links 7.2.2, qr_flutter 4.1.0 and
  reviewed transitives. OpenAPI, schemas/ER, flow, permission/security/threat
  models, key/device docs, dependency governance, modules, scenario catalog,
  contributor shortcuts, bug/status and changelog updated in the same change.

## Tests added and maintained

- `guardian_onboarding_test.dart`: strict links, pending isolation, actual
  libsodium/SQLCipher retained-state handoff with restricted child resources,
  lost approval response/exact retry, revocation, malformed profile and orphaned
  progress after outbox clearing.
- `guardian_screen_test.dart` + `support/guardian_scenarios.dart`: prepared owner
  and empty guardian screens, QR/share/copy contract, explicit acceptance/code
  comparison/permission approval, delivered calendar and read-only UI, malformed
  input without request, expired QR and share-failure copy fallback.
- `integration_test/guardian_onboarding_scenario_test.dart`: same three prepared
  journeys on native Flutter engines, no real auth prompts or message dispatch.
- `test_guardian_onboarding_api.py`: real PostgreSQL pending/cross-family
  isolation, stale device/hash, resource subset/duplicate rejection, approval
  retries, baseline filtering, read-only writes, downgrade safety, revocation,
  renewed/cancelled/expired invitation handling and open-request quota.
- `guardian_postgres_roundtrip_test.dart` + explicit
  `test_guardian_postgres_mobile.py` host: real Dart HTTP clients, independent
  SQLCipher/libsodium installations, stubbed WebAuthn boundary, expired retained
  relay, actual signed sealed keys/scoped handoff, retries and revocation.
  Its synthetic-only expiration route is never in the shipping backend.
- `./test --ios --scenario guardian` / Android counterpart added to the explicit
  native allowlist, with runner regression updated. Backup portability remains
  excluded. Existing migration tests support schema 7 and guarded teardown.

## Initial executed results (before authorized failure investigation)

Only command exit statuses were reviewed. Failure identities, assertions,
stack traces, build-vs-execution failure phase and test counts have not been
inspected or inferred. Logs are ignored under `test-results/bug004-*`.

| Check | Result / log |
| --- | --- |
| Fresh isolated `sarti_bug004` PostgreSQL setup | PASS |
| Alembic upgrade head (0007) | PASS; migrations.log |
| Full backend Pytest with coverage: unit/API/security/contracts/migration | PASS; backend.log; opt-in mobile host skipped here |
| Ruff format/lint | PASS; ruff-format.log, ruff.log |
| Strict Mypy / Bandit | PASS; mypy.log, bandit.log |
| Runtime pip-audit | PASS; dependency.log |
| Dart format | PASS; format.log |
| Flutter analysis | **FAIL**, exit 1; analyze.log |
| Full Flutter unit/widget suite with coverage | **FAIL**, exit 1; flutter.log; opt-in host-dependent test skipped here |
| Explicit real guardian HTTP/PostgreSQL/Dart host | **FAIL**, exit 1; http-host.log, http-mobile.log |
| iPhone 18 Pro / iOS 27 prepared guardian command | **FAIL**, exit 1; ios.log |
| Android API 35 emulator setup | PASS; emulator-startup.log |
| Android API 35 prepared guardian command | **FAIL**, exit 1; android.log |
| Shipping Android debug APK build | PASS; android-build.log |
| Shipping unsigned iOS simulator debug build | PASS; ios-build.log |
| Current-source Docker build/startup, live and ready health | PASS; docker-smoke.log |
| Python test-runner/version unit tests | PASS; tooling.log |
| OpenAPI generation, version integrity 0.1.0+1, whitespace | PASS |
| OSV new exact Dart packages | No listed advisories for 14 versions; osv.json |
| Cached pinned Gitleaks staged scan (network disabled, read-only, no mounts) | PASS; secret-scan.log |

No failing test/check was diagnosed or retried. Native and host commands were
independent planned checks, not retries of the full Flutter suite. Build success
establishes compilation only and does not establish journey/provider success.

## Security and platform limits

Initial mobile and cross-layer failures blocked closure; the authorized
follow-up below resolves them. Physical/provider acceptance remains separate. Source design keeps private names/content in scoped ciphertext
and protected local storage. Packages were reviewed for targeted source logging/
network paths and licenses; zero listed advisories is not proof of security.

Share/copy tests inject capture adapters, so no messages were sent and no user
clipboard was overwritten. Initial native commands failed; follow-up native QR rendering and workflow
commands pass. No successful camera scanning is inferred. Real camera decode, OS share/clipboard,
cold/warm custom links, uninstalled-app fallback, configured production passkeys,
Keychain/Keystore and two physical phones remain unverified. There is no HTTPS
universal-link domain or web/app-store landing page in this fix.

A configured authenticated Sarti service is required; an offline-only developer
build cannot enroll a guardian. New onboarding requires upgraded participating
clients that understand the family-profile operation. Initial handoff expires
in seven days and does not grant owner backup authority to a restricted guardian.
Existing open event conflicts need owner resolution first; BUG-017 remains open.
One local family and existing recovery/unknown-historical-key limitations remain.
Neither backup portability direction ran; Android-to-iOS is explicitly deferred.

## Authorized targeted follow-up — 2026-10-13

Maintainer requested “check failed test and fix”. Inspected only failing analysis,
assertion and exception blocks. Corrected:

- Unsupported `QrImageView.data` test accesses: compare the rendered QR image
  against the expected token-only painter, and compare share/copy against that
  expected invitation link. No QR-content assertion was removed.
- Fixture sync-engine double initialization: allow the guardian relay adapter
  to replace the prepared test engine.
- Actual handoff defect: `applySharedHousehold` omitted the required `applied_at`
  column. Insert both named fields inside the existing transaction, preserving
  atomic profile/readiness/replay bookkeeping. Add timestamp and repeated-refresh
  regression assertions; no schema or protocol change.
- Two missing braces and an unnecessary import. A temporary exception rethrow
  used with synthetic tests was removed; shipping bounded error handling remains.

Follow-up checks: Dart formatting PASS; analysis PASS; full Flutter suite PASS
(136 passed, 2 opt-in tests skipped); explicit real HTTP/PostgreSQL/Dart guardian
handoff PASS. iPhone 18 Pro / iOS 27 and Android API 35 prepared guardian
journeys PASS (3 scenarios on each). Logs: `bug004-fix-format.log`,
`bug004-fix-analyze.log`, `bug004-fix-flutter.log`, `bug004-http-host.log`,
`bug004-http-mobile.log`, `bug004-fix-ios.log`, `bug004-fix-android.log`.
No backend, schema, dependency, API-wire or ADR changes were needed. Original
backend/security/migration/dependency/build results above remain applicable;
those suites were not repeated during the targeted fix. Version 0.1.0+1 and
whitespace checks PASS; cached pinned offline secret scan PASS
(`bug004-fix-secret-scan.log`). BUG-004 is resolved for implemented/automated
scope; physical/provider checks listed above remain unexecuted. No other bug or
stage was started.
