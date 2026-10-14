# Remaining-bug remediation verification

Date: 2026-10-14. Development version 0.5.0+5; no public release tag.
Scope: BUG-005/012/013/014/017/021 only. Maintainer requested the six fixes together,
tests, failed-test-only investigation and targeted fixes/reruns. No next stage.
Status: five defects resolved; BUG-005 implementation verified, live provider
acceptance explicitly deferred. All executed final checks passed.

## Features and changed areas

- BUG-013: `event_parser`, proposal merger/dialog, repository/controller and
  calendar editor. Separate clauses retain explicit shared date/activity;
  unknown/ambiguous fields need clarification. Noon/midnight, durations and end
  ranges, visible one-hour defaults, editable minutes/end preview. Each suggestion
  is reviewed; final approval commits all events/relationships/outbox atomically.
  Invalid second writes roll everything back. Existing timezone/recurrence data
  is preserved on manual edit; end display uses elapsed time and event zone.
- BUG-014: calendar snackbar has five-second expiry, close control and current
  feedback replacement. OS accessibility behavior is respected. Undo selects a
  saved event and opens editable review; no automatic deletion. Delete is explicit,
  Cancel/dismiss preserves saved content, Save requires valid dirty fields,
  reverting edits disables Save; stale/removed events cannot be overwritten.
  Dialog controllers are disposed after route transitions complete.
- BUG-017: repository compares authoritative persisted event vectors instead of
  obsolete outbox snapshots. A remote merged resolution retires only the same
  event/resource conflicts whose two parents are covered. Other alternatives stay;
  stale cards and snapshots cannot overwrite/reopen resolved state.
- BUG-021: `FamilyManagementScreen` unifies names, children, People & pets, existing
  guardian invitation/removal and retention. Owner UI guards, scoped name changes,
  offline guidance and encrypted `household_shared`/child profile operations;
  existing server authorization stays authoritative. No display name goes into
  server plaintext metadata; edits never change memberships or key permissions.
- BUG-012: `.github/workflows/ci.yml`, `ci_ios_tests.py`, runner tooling. Available
  iPhone/runtime discovery, all eight allowlisted prepared native journeys,
  per-scenario summary, failure logs/screenshots, seven-day artifact retention.
  Missing runtime fails rather than silently skipping. No portability tests.
- BUG-005: accepted ADR-037 implementation: authenticated explicit optional
  server broker, strict token schema, active-device rejection, current consent v3,
  no client-held provider credential, atomic daily/global caps, safe errors,
  content-free logging, bounded HTTPX deadline/streaming and no redirects/retries.
  Phone filters fresh labels and independently checks response source evidence.
  Direct mobile Gemini SDK removed; no new package. Default server disabled.

## Approval and privacy

Maintainer expressly approved ADR-037 implementation, including temporary Sarti
plaintext scheduling-token processing and usage metadata; billing/deployment/
real-family-data activation excluded. Maintainer then explicitly deferred live
provider testing and confirmed discussion of native-first use. Native on-device
AI remains primary on supported devices; deterministic local parsing remains
available everywhere. Gemini is optional, not required and never a silent fallback.

The optional broker is outside sync/backup E2EE. No prompts/responses/content
hashes or reverse maps persist server-side; Google/provider handling must still
be verified before activation. Runtime flags are not proof of paid-service
eligibility. Counts persist for 35 days, purge on reservations and required daily
maintenance; adult deletion purges its rows. No family-scoped counter exists.

## APIs, migrations, ADRs and documentation

- Accepted ADR-037 documented with approval and explicit activation boundaries.
  Existing encrypted calendar/profile/conflict ADRs preserved; no new crypto.
- Add `/v1/ai/capability` and `/v1/ai/proposals`, strict generated OpenAPI.
  No calendar mutation endpoint. Every cloud response/error is no-store.
- Append PostgreSQL 0010: scope/bucket/count/expiry, index and account-delete
  trigger. Existing encrypted data preserved; actual downgrade/re-upgrade tested.
  Local SQLCipher remains v9; batch writes reuse existing tables/transactions.
- Updated README/version/changelog, architecture/context/data flows, AI/privacy
  messaging and disclosure, permission/security/threat model, database/schema/
  migration history, module catalogue, cloud API, deployment activation guidance,
  scenarios/testing strategy, contribution shortcuts, BUGS and STATUS.
- Versions follow ADR-030: minor 0.5.0+5 for the additional P0 capabilities/API.
  Local iOS signing edits are retained and excluded from the commit.

## Executed checks

| Check | Final result |
| --- | --- |
| Flutter full coverage regression | PASS — 212; 2 opt-in HTTP skips, both hosts separately executed |
| Flutter format/analysis | PASS |
| Backend full with both real mobile HTTP hosts | PASS — 57; 91.25% coverage; PostgreSQL 0010 |
| Native iOS all eight prepared journeys | PASS — 69 distinct checks across eight journeys, including targeted reruns/DST |
| Native Android combined regressions | PASS — 9 combined + 1 targeted DST check |
| Normal Android/iOS builds | PASS — normal debug APK and unsigned iphoneos Runner.app |
| Backend Ruff format/lint, strict Mypy, Bandit | PASS |
| Python version/CI-runner tooling | PASS — 11 |
| Pinned runtime pip-audit | PASS |
| Docker rebuild/start/migration and live/ready health | PASS |
| Generated OpenAPI regeneration/drift contract | PASS in full backend run |
| Version integrity | PASS — 0.5.0+5 |
| Whitespace and staged pinned offline Gitleaks | PASS |

Logs are ignored under `test-results/allbugs-*`; native CI logs/screenshots under
`test-results/ios-ci/`. Real HTTP fixtures use existing bug004/bug011 log names.
Commands: `flutter test --coverage --reporter expanded`, `flutter analyze`,
`dart format --output=none --set-exit-if-changed lib test integration_test`,
`make backend-check`, `python3 -m unittest discover -s scripts -p 'test_*.py'`,
`python3 scripts/version.py check`, runtime pip-audit and Docker health probes.
Backend runner creates isolated `sarti_allbugs_test`, upgrades to head, and runs
pytest coverage with both mobile HTTP host opt-ins. Local developer DB is not
used for destructive test migration fixtures.

The exact CI runner (`python3 scripts/ci_ios_tests.py`) ran locally. Failures were
limited to the pre-fix stale-resolution regression and an off-screen Repeat
control in the older native calendar fixture. Only those journeys were rerun. The calendar fixture also explicitly dismisses
the keyboard and checks the whole Repeat control is on-screen/toggled before
saving. The additional DST check passed on both native platforms.
The targeted DST check exposed double-counting colon times; fixed clock token
matching and require explicit clarification when duration conflicts with an
end range across DST. Its targeted unit rerun passed.
Earlier failed unit suites exposed immediate dialog-controller disposal,
off-screen control targeting and obsolete immediate-Undo expectation. Fixes
preserve the approved UX/security assertions. The encrypted family fixture needed
its explicit recipient read grant; no application permission was weakened.

## Security evidence and limits

Real SQLCipher/libsodium fixtures verify atomicity, profiles and conflict state.
Real PostgreSQL/HTTP fixtures cover tenant/device/resource authorization,
revocation, replay/epochs and encrypted peer conflict retirement. Concurrent
connections prove quota reservation limits; account purge/expiry/migrations and
phone/server grammar parity are tested. Synthetic provider capture proves fixed
host/header-only secret/no identifiers, strict bounds/errors and no automatic
retry; it does NOT prove a real provider's availability, billing or retention.

Live Gemini test NOT RUN, explicitly deferred. No billing activated, provider
request made or family information sent to cloud. Eligible physical-device
native inference, passkeys, Keychain/Keystore, APNs/FCM, camera/share/email delivery,
OS lifecycle and production infrastructure remain separate release validation.
Android→iOS backup portability NOT RUN; no transfer direction newly authorized.
Remote GitHub CI status is not inferred from local results.

Recommended next work: physical/provider acceptance or next stage only after
maintainer direction. Do not automatically begin Stage 4 or cloud activation.

Provider compatibility limit: Google's current model documentation restricts
Gemini 2.5 access to projects/users with prior usage. The implemented 2.5 adapter
therefore is not a ready-to-activate choice for a new project. Before any cloud
activation, review an eligible current model/adapter and perform the separately
authorized live synthetic check. Native/local use is unaffected.
Source: [Gemini 2.5 Flash-Lite access notice](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite).
