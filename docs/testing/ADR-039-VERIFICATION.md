# ADR-039 verification — family calendar retention

Date: 2026-10-13 (America/Vancouver). Version: 0.3.0+3; private beta, no public
release tag. The maintainer explicitly approved ADR-039 after confirming mobile
calendar-only effect, family account scope and admin-managed configuration.
No Stage 4, production deployment or external service activation is included.

## Delivered behavior

Calendar menu → Calendar retention exposes one family policy: one week (default),
one month, three months, one year, Never. Owner/delegated calendar admins review
and apply changes; ordinary writers cannot change policy. New family creation
adopts one week; legacy server/local families require explicit adoption. Counts
are local previews, not a claim to inspect other adults' private appointments.

Expiry measures appointment end, preserves future/ongoing appointments and
active/unbounded recurring series, and proves finite-series completion before
removal. Monthly/yearly boundaries clamp unavailable dates in the event timezone.
Cleanup uses current authenticated policy after bounded full catch-up and runs
on foreground sync/five-minute foreground intervals. Pending edits/open conflicts
or changed shared copies defer it. Never cannot undo earlier removal.

Shared deletion originates from current calendar admins; private deletion stays
on the author's resource/device. Expired event details, including old manual
tombstone details, relationships and obsolete acknowledged payloads are removed
with SQLCipher secure-delete. Minimal identities/vectors retain replay protection. Reviewed Keep decisions
live in `event_versions.retention_keep_vector`, survive personal recovery and
are included in authorized initial guardian handoff.
Exact pending retry bytes are preserved. Concurrent edit/deletion has explicit
Keep/Delete review; Keep synchronizes an exemption for that event vector.
Causally dominating resolutions retire retention conflicts; stale replays cannot
resurrect removed history. Independent new alternatives fail closed instead of
silently replacing an unresolved alternative.

## Changed files, APIs and migrations

- Backend household API/schema: family configuration GET/PUT at
  `/v1/families/{family_id}/calendar-retention`, bounded period/revision fields,
  server-side owner/calendar-admin checks and revision conflicts. Family-create
  `retention_enabled` supports legacy-local adoption. Generated OpenAPI updated.
- PostgreSQL `0009_calendar_retention.py`: bounded policy metadata; existing rows
  inactive/revision zero; configured-policy downgrade guard; ciphertext unchanged.
- Mobile `sarti_database.dart`: SQLCipher v8, minimal deletion/retention-conflict
  tables and secure-delete; migration never deletes existing appointments.
- `calendar_retention.dart`, repository part/store, controller/screen/menu:
  eligibility, local removal, scope checks, settings/preview and conflict review.
- Network/bootstrap/sync: policy transport/cache, foreground catch-up/cleanup,
  `retention_deleted`/`retention_kept`, initial guardian deletion-state handoff.
- Backup sanitization excludes private deletion/conflict rows using existing
  scope rules. Family-only recovery gets a local automatic-cleanup pause marker;
  backup format/crypto and accepted recovery causality remain unchanged.
- Shared prepared scenarios/native entry point, migration/crypto, policy-client,
  backup privacy and real API/migration tests. `./test --ios --scenario retention`
  and Android counterpart select the native suite; `all` includes it.
- Architecture/ADR index, API, schemas/migration history, permission/security,
  privacy, module, sync, scenario/strategy, STATUS, BUG-022 mitigation and
  changelog/version documents updated together. ADR-022 points to accepted ADR-039.
- Existing local Xcode signing edits are preserved and excluded from the commit.

## Executed checks and results

Final checks pass on the durable Keep-state implementation: Flutter **184 pass,
two opt-in skips**; backend **33 pass**, both HTTP/Dart contracts enabled,
**91.51%** branch-inclusive coverage; **12 prepared scenarios pass on each native
platform**. The targeted retention/migration/backup suite also passes 21 cases.
No failed check remains in the final runs.

| Check | Command / scope | Result |
| --- | --- | --- |
| Flutter unit/widget/regression | `flutter test --coverage --reporter expanded` | PASS, 184 tests; two opt-in HTTP skips covered by enabled hosts |
| iOS simulator prepared retention | `flutter test integration_test/calendar_retention_scenario_test.dart -d A351256A-6255-4285-A1AE-5624594A08FD` | PASS, 12 scenarios; iPhone 18 Pro / iOS 27 simulator |
| Android API 35 emulator retention | Same entry point, `-d emulator-5554` | PASS, 12 scenarios; Android API 35 emulator |
| Backend full + HTTP/Dart | Isolated `sarti_retention_test` PostgreSQL DB; both opt-in hosts enabled | 33 pass; 91.51% coverage |
| PostgreSQL migration | Fresh head 0009; upgrade/downgrade/guard; encrypted bytes preserved | PASS |
| SQLCipher migration | Encrypted v7→v8 file; event/exact pending envelope retained; wrong key rejected | PASS in full Flutter run |
| API contract | FastAPI-generated OpenAPI and committed snapshot | PASS in full backend run |
| Backend static/security | `make backend-check` (Ruff format/lint, Mypy, Bandit) | PASS |
| Flutter format/analysis | Dart format / `flutter analyze` | PASS, no analyzer issues |
| Tooling regressions | `python3 -m unittest discover -s scripts -p 'test_*.py'` | 8 pass |
| Version integrity | `scripts/version.py check` | PASS, 0.3.0+3 |
| Docker build/migrate/health | `docker compose up --build --wait`; live/ready HTTP endpoints | PASS, both HTTP 200 |
| Pinned runtime dependency audit | `pip-audit -r backend/requirements-runtime.lock` | PASS, no known vulnerabilities |
| Staged secret/whitespace scan | Pinned offline Gitleaks / `git diff --check` | PASS, pinned offline staged scan and whitespace |

Ignored logs: `test-results/retention-*.log`; enabled Dart hosts also use their
existing ignored `bug004-http-mobile.log` / sync-host log paths. Full successful
logs were not analyzed; only failed test/analysis blocks were inspected.

Earlier failures were corrected: generated OpenAPI drift after API additions,
missing repository-extension imports, an unclosed brace in the new retention
helper, and migration-test lint line lengths. A guardian HTTP/Dart run failed
solely while that brace was broken; the final complete backend rerun passes.
No authorization, crypto or data-preservation assertion was weakened. Final
review also moved Keep exceptions into durable causal state and added actual
personal-snapshot/staging and initial-handoff regressions; all final runs above
include the resulting implementation.

## Security findings and remaining limits

- BUG-022 remains open: family-only recovery's causal/key continuation is not
  repaired by retention. Such recovered calendars pause automatic cleanup;
  minimized deletion refuses to erase an existing event with missing causal
  state. This mitigation does not claim full recovered-family convergence.
- Existing encrypted exports, hosted snapshots, provider copies and disconnected
  guardian copies can contain older history. Retention does not rewrite/delete
  those backups or extend the server's seven-day relay lifetime.
- A configured authenticated service is required to manage the family policy
  and initiate cleanup with current authority. Offline-only builds/phones wait
  for connection; exact background/deletion timing is not promised.
- Native tests use prepared logical devices, real platform SQLCipher/libsodium
  and synthetic relay/identity fixtures. They establish native builds/scenarios,
  not physical passkeys, Keychain/Keystore guarantees, APNs/FCM or real phone-to-
  phone background delivery. Physical device/background/accessibility validation
  remains unexecuted.
- The two normal Flutter HTTP skips are covered by the separately enabled real
  backend HTTP/Dart hosts; do not call the default Flutter run skip-free.
- Android→iOS backup portability remains deliberately unrun. No cross-platform
  backup portability direction was needed or run for this feature.
- Native CI coverage remains BUG-012. GitHub CI is triggered by push; its result
  is not inferred from local checks. No new provider/dependency is introduced.
- Deploy backend/migration 0009 before coordinated 0.3.0+3 beta-client upgrades;
  older clients do not understand the new encrypted operation kinds.

Recommended next authorized task: address BUG-022 through its own approved
recovery design/test work, then physical acceptance. No next bug/stage is started
by this report.
