# BUG-019 — First-family creation controls

Date: 2026-10-13. Resolved for automated scope; physical-iPhone retest pending.

## Change and scope

A maintainer physical-phone report identified absent Add Event after Create
family. The bootstrap computed false canWrite/canManageChildren before family
creation, while only its child calendar listened for changes. Wrapping the
controller-dependent bootstrap presentation in ListenableBuilder recomputes the
existing checks as soon as a family exists. It does not change authorization.

Changed implementation: `authenticated_calendar_bootstrap.dart`. Prepared
regressions: `bootstrap_permission_refresh_test.dart`. Updated bug/status,
scenario catalog, module documentation and changelog. No ADR, API, database,
migration, crypto or dependency changes. Local user iOS signing/project/plist
edits were not modified or included in the fixing commit.

Four cases cover initial family creation, existing owner, read-only guardian
and revoked guardian. Creation prerequisites use prepared SQLCipher storage,
libsodium keys and injected secret/reminder adapters. Family creation itself is
under test through UI. Event/child controls appear immediately; opening and
cancelling the editor does not write an event. Range/controller notifications
never reveal mutation controls to restricted roles. Widgets unmount before
fixture databases/keys close.

## Executed

- Dart formatting: PASS (`test-results/bug019-format.log`).
- Flutter analysis: PASS (`bug019-analyze.log`).
- Full Flutter unit/widget suite: PASS, 144 tests, 2 opt-in host tests skipped
  (`bug019-flutter.log`). Includes existing privacy/sync/guardian regressions.
- Version integrity: PASS, 0.1.0+1; whitespace: PASS.
- Offline staged secret scan: PASS (`bug019-secret-scan.log`), cached pinned
  image with no network/mounts and read-only container.

No failed logs inspected. Native builds/scenarios and physical-phone retest not
run; this change has no native platform/dependency modification. Backend unit/
API/PostgreSQL/migration/HTTP, Docker and dependency suites not rerun because
server/contracts/schema/dependencies are unchanged. Backup portability excluded.
No production/provider/passkey/protected-storage compatibility claim follows
from these fixtures. Remote CI result is not yet reviewed.

The reported Today navigation (BUG-018), optional guided setup (BUG-020), family
management hub (BUG-021) and existing child-colour BUG-015 remain separate. Setup
must preserve ADR-022's optional details and immediate calendar access. Adult
invitation/removal requires the configured authenticated service; offline builds
cannot exercise it. Recommended next UI fix: BUG-018, only after the maintainer's
next instruction. BUG-005 broker approval remains independently pending.
