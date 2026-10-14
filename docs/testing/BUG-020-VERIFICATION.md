# BUG-020 — Optional family setup

Date: 2026-10-13. Resolved for automated scope; final follow-up results below.

## Scope and decisions

Maintainer requested the next bug after BUG-018. Implement optional family setup
within accepted ADR-022 progressive onboarding. No superseding ADR, backend API,
schema/migration, crypto, dependency or version change. Family/child save calls
reuse existing SQLCipher and resource-scoped outbox/sync infrastructure.

Changed implementation:
- `family_setup_screen.dart`: draft optional names, explicit Continue/defaults,
  Skip setup and optional post-creation children step; clear per-child save rules.
- `child_profile_editor.dart`: shared named-colour picker, unused defaults,
  explicit palette reuse, optional alias validation and separate sharing consent;
  family identity and owner-cache checks at save; bounded errors/no content logs.
- CalendarScreen routes Create family to setup and uses the common child editor.
- CalendarController exposes the existing canManageFamily owner-cache predicate;
  bootstrap reuses it. Invalid cache JSON fails closed. No server auth change.

Associated BUG-015 creation work is a candidate only; existing profile colour
editing, old duplicate-colour correction and shared-event indicators remain open.
No general family-management hub or adult-management changes (BUG-021).
User iOS signing/project/plist changes remain untouched and excluded from commit.

## Added / maintained scenarios

Seven `FAMILY-*` scenarios in `support/family_setup_scenarios.dart`, registered by
`family_setup_test.dart` and native `calendar_add_event_scenario_test.dart`:
- Draft names/back without writes; explicit names and two child colours.
- Optional children and preservation of individually saved profiles on Back.
- Invalid alias retains draft and creates no child/outbox operation.
- Revocation while form is open disables writes.
- Palette exhaustion requires explicit colour reuse.
- Selected colour through actual libsodium/SQLCipher to a controlled authorized
  receiver with explicit sharing consent.

Existing ONB-MOB-001 and BOOT-PERM-001 use Skip setup to preserve progressive/
first-family-control assertions. Existing child widget/native tests scroll to
explicit sharing consent in the expanded shared form; assertions are retained.
Fixtures seed prerequisites directly except actions under test, unmount widgets
and dispose controllers/databases/keys. No physical phone or real family data.

## Executed results

The maintainer authorized failed-test-only inspection, spot fixes and reruns on
2026-10-13. Failed cases tapped Add before a scheduled state rebuild had enabled
its callback (including after colour/sharing selection). The next action could
therefore act on a still-open dialog. Tests now settle pending frames before Add;
all original persistence, permission and sharing assertions remain intact. No
application exception was hidden or assertion relaxed.

Follow-up checks: focused family setup + child-sync tests PASS (23); full Flutter
suite PASS (158, 2 opt-in skips); Dart format and analysis PASS. Native reruns are
in progress. Follow-up logs use bug020-focused.log, bug020-flutter-rerun.log,
bug020-format-rerun.log and bug020-analyze-rerun.log.

Original results (superseded by follow-up checks where listed above):

| Check | Result / ignored log |
| --- | --- |
| Dart formatting | PASS; bug020-format.log, bug020-format-final.log |
| Flutter analysis | PASS; bug020-analyze.log |
| Full Flutter unit/widget suite with coverage | FAIL; bug020-flutter.log |
| iOS simulator calendar/onboarding command | FAIL; bug020-ios-calendar.log |
| iOS simulator child-sync command | FAIL; bug020-ios-child.log |
| Android emulator calendar/onboarding command | FAIL; bug020-android-calendar.log |
| Android emulator child-sync command | FAIL; bug020-android-child.log |
| Version 0.1.0+1 / whitespace | PASS |
| Final staged offline secret scan | PASS; bug020-secret-scan.log; cached pinned image, no network/mounts, read-only container |

Runner-reported Flutter failures:
- FAMILY-MOB-002 named family, two coloured children and open calendar
- FAMILY-MOB-003 child setup is optional and back preserves explicit saves
- FAMILY-MOB-005 palette exhaustion requires explicit colour reuse
- FAMILY-SYNC-001 shared colour selection reaches authorized encrypted receiver

## Unexecuted checks / limitations

No physical-phone, VoiceOver/TalkBack, actual passkey/protected-storage, real
provider/transport or production two-phone acceptance is claimed. The native
commands failed; no successful journey or build phase is inferred from them.
Backend unit/API/PostgreSQL/migration, OpenAPI regeneration, Docker rebuild and
new dependency checks not rerun: those code/contracts/schema/versions are
unchanged. Backup portability excluded; no cloud inference activated.
Security regressions are included in the failed suite; this is not a claim that
all security/functional acceptance passes. No security failure cause was inferred.

Maintainer follow-up authorized focused diagnosis and reruns. BUG-020 remains
open pending native verification; BUG-015 editing/legacy-colour work remains open.

## Final follow-up — 2026-10-13

BUG-020 is resolved for automated scope in 0.2.0+2. Full final Flutter suite:
169 passed, two opt-in HTTP cases skipped here and executed separately through
backend fixture hosts. Seven FAMILY scenarios plus CAL-MOB-001 and
CHILD-NATIVE-001 pass on both iPhone 18 Pro/iOS 27 and Android API 35.
The stale native fixed-purple assertion now compares the selected child colour;
the calendar child tap ensures its actual visible position. No weakened persistence,
sharing, isolation or revocation assertion. See adr038-ios.log / adr038-android.log
and final adult/colour reruns for the combined change. Formatting and analysis
pass; provider/physical-phone claims remain excluded. Historical failed results
above are retained as the investigation trail, not the current acceptance result.
ADR-038 API/schema changes belong to the separately approved adult/pet feature,
not the original setup fix. Source signing/project/plist changes remain excluded.
