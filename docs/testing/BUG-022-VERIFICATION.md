# BUG-022 verification — family recovery continuation

Date: 2026-10-13 (America/Vancouver). Development version 0.4.0+4.
Maintainer approved ADR-040 with “sounds good” after the concrete proposal and
historical expected-red reproductions in BUG-022-DESIGN-REVIEW.md.
Status: resolved; all executed final checks passed.

## Delivered behavior and files

- `mobile/lib/src/features/backup/backup_recovery.dart`: real encrypted family
  snapshot scope/history validation, independent snapshot key, intent capture,
  staged/protected activation; old credentials/envelope/cursors reset.
- `mobile/lib/src/core/database/sarti_database.dart`: append-only local v9
  recovery-state/intent tables; actual v8 upgrade and incomplete legacy block.
- `calendar_recovery_store.dart`: scoped validation, original pending intent,
  quarantine, explicit fresh operation and replacement-device vector, atomic
  reviewed mapping, receipt/causal reconciliation and completed-body removal.
- `family_recovery_coordinator.dart` / `family_recovery_screen.dart`: fresh
  authority/current keys, download-only catch-up, prepared review/conflict/child
  sharing flow, current-policy history review, deliberate retention resume.
- Sync engine/key preparation/authenticated bootstrap/calendar controller/UI:
  prevent ordinary writes, private-key recovery, resource recreation, implicit
  publication and unreviewed outgoing rows; exact family/resource/kind/body/vector
  binding protects approved retries. Existing crypto/AAD/epoch controls remain.
- Retention store removes completed recovery bodies with expired content and
  preserves pending/quarantined intent. Reconciliation also discards completed
  intent immediately; applied IDs/minimal deletion state carry replay protection.

## Contracts, documentation and governance

Accepted ADR-040 supersedes family clearing in ADR-032 and unconditional pause
in ADR-039, preserving ADR-038 private exclusion and personal safeguards.
Local schema v9 requires a compatible snapshot reader: ADR-030 pre-1.0 minor
increment to 0.4.0+4. No new dependency/service, API endpoint, PostgreSQL revision
(still 0009), backup-envelope version (still v2) or server plaintext storage.
Generated OpenAPI is unchanged; its existing API-contract version is independent
of the application development version.

Updated architecture/ADR index, data/key/sync flows, backup API usage, local schema
and migration/ER documentation, module catalog, permission/security/threat models,
privacy disclosure, UI flows, scenarios/testing strategy, contribution shortcuts,
STATUS, BUGS and CHANGELOG. Local iOS signing changes are deliberately excluded.
No public release tag, production deployment, next bug or next stage.

## Test design and evidence

Prepared independent SQLCipher source/replacement files, actual libsodium backup
and relay, fresh device identities, old/current key epochs, direct review-screen
entry and teardown. Faults: lost receipt, malformed AEAD, stale authority/policy,
missing causal history, foreign scope and unreviewed outgoing mutation. Current
recipient sharing must be chosen again; old profile consent cannot silently widen.

Expanded `GUARD-HTTP-001` invokes `RECOVERY-HTTP-001`: actual local HTTP/FastAPI/
PostgreSQL device replacement, former-session 401, opaque snapshot upload/download,
local staged restore, signed sealed-key grants, current-epoch reviewed upload and
explicit cleanup resume. WebAuthn is the host's explicit stub; crypto, storage,
HTTP and authorization are real. Existing backend tenant/invitation/replay/epoch/
revocation and migration tests remain in the full run.

Initial failure: the HTTP test adapter supplied its registration string instead
of the base64url authentication credential identifier. Corrected the fixture;
spot rerun passed. Earlier focused failures in reviewed-operation mapping and
widget visibility were fixed without weakening approval/security assertions.
Final review added completed-intent minimization coverage. Only failing output
was inspected for diagnosis; successful output used for result summaries. The initial redacted secret scan
matched prose beside “keys”; reworded that sentence and reran the unchanged
pinned scanner without an exclusion. No credential was found.

## Final executed checks

Final results:

| Check | Result |
| --- | --- |
| Flutter full unit/widget/crypto/backup/security/migration suite with coverage | PASS — 202; 2 opt-in HTTP skips, separately executed via hosts |
| Backend full with both mobile HTTP contracts, real PostgreSQL migration | PASS — 33; 91.51% coverage; Alembic head 0009 |
| Native iOS recovery + retention minimization | PASS — 15; iPhone 18 Pro simulator, iOS 27 |
| Native Android recovery + retention minimization | PASS — 15; emulator-5554 |
| Flutter analysis / format | PASS |
| Backend Ruff format/lint, Mypy, Bandit (`make backend-check`) | PASS |
| Pinned runtime dependency audit (`pip-audit -r backend/requirements-runtime.lock`) | PASS |
| Python version/test-runner tooling | PASS — 8 tests |
| Version integrity | PASS — 0.4.0+4 |
| Generated OpenAPI regeneration/drift | PASS — no change |
| Docker rebuild/start, live/ready health endpoints | PASS |
| Whitespace / staged pinned offline Gitleaks | PASS |

Commands: `flutter test --coverage --reporter expanded`, `flutter analyze`,
`dart format --output=none --set-exit-if-changed lib test integration_test`,
`make backend-check`, `python3 -m unittest discover -s scripts -p 'test_*.py'`,
`python3 scripts/version.py check`. The isolated PostgreSQL runner upgrades
`sarti_bug022_test` to Alembic head then runs pytest with coverage and both
`SARTI_RUN_MOBILE_CONTRACT=1` / `SARTI_RUN_GUARDIAN_CONTRACT=1`.
Native entrypoint: `integration_test/family_recovery_continuation_scenario_test.dart`;
shortcut `./test --ios --scenario recovery` (or `--android`). Ignored result logs
use `test-results/bug022-*`; underlying HTTP hosts use bug004/bug011 logs.

## Security and acceptance limits

- Fresh server authority and verified current grants gate writes; saved historical
  keys never restore membership, replaced credentials or private access.
- Snapshot/available-relay catch-up cannot prove latest completeness beyond the
  seven-day TTL. UI discloses snapshot time and that gap; no fake complete state.
- Previously stripped/incomplete legacy snapshots stay readable and blocked;
  obtain a complete authorized source. No fabricated vectors, silent conflict
  overwrite, deleted-calendar recreation or implicit child-sharing expansion.
- Native tests use simulator/emulator SQLCipher/libsodium and prepared UI with
  synthetic relay/authority; real HTTP host separately verifies server integration.
  Physical passkeys, Keychain/Keystore, OS process interruption/background behavior,
  provider delivery and production backup retention are NOT verified by these.
- Android→iOS backup portability NOT RUN, per explicit instruction. No new
  cross-platform claim. Separate personal pending-write continuation is not
  declared complete by this family-only fix.
- BUG-012 native CI coverage gap and other open defects remain. CI after this
  push is not claimed passed until GitHub reports it.

Recommended next work: obtain maintainer direction for the next open defect;
BUG-021 family management remains separate. Do not start it automatically.
