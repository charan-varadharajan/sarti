# BUG-016 — Kalender integration verification

Date: 2026-10-12. Status: **Resolved after expectation corrections; all rerun suites pass.**

## Scope and approval

The maintainer selected Kalender and authorized implementation/test execution.
ADR-033 records that approved choice without superseding earlier ADRs. No Stage 4
work is included. The follow-up instruction authorizes fixing only the failing tests and rerunning
verification. No other open defect is included in this follow-up.

## Implementation

- Pinned `kalender` 0.33.0 and its resolver lock; dependency/license/privacy
  review documented in ADR-033 and DEPENDENCY-GOVERNANCE.md.
- New `calendar_occurrence_adapter.dart` creates transient read-only occurrence
  objects from Sarti's recurrence engine. UTC ranges retain elapsed duration;
  labels use the display zone, overnight end dates and distinct DST offsets.
  The adapter filters wrong family/resource scope, cancellation and deletion.
- New `family_calendar_view.dart` supplies day/week time grids, a month grid,
  previous/next/Today navigation, phone-width week scrolling, month selected-day
  agenda and an agenda toggle. Event tiles retain stored child colours and text
  labels. Existing identical-colour assignment remains BUG-015.
- Package create/drag/resize paths are disabled. Event taps call the existing
  explicit editor; browsing does not write to local storage or the sync outbox.
- `calendar_screen.dart` delegates layout to the new view. Existing agenda
  journeys select the agenda for label/colour assertions. New grid tests cover
  spatial layout independently.
- `./test --ios --scenario grid` and `./test --android --scenario grid` select
  the prepared grid suite. Default native runs include it; backup portability
  stays excluded. BUG-012 (native CI execution) remains open.

## Tests added

- `mobile/test/calendar_occurrence_adapter_test.dart`: four adapter regressions
  covering scope/interaction restrictions, overnight carry-in/exact boundaries,
  recurrence/timezone conversion and spring/fall DST elapsed duration.
- `mobile/test/calendar_grid_test.dart` and shared
  `support/calendar_grid_scenarios.dart`: three prepared grid journeys covering
  views, duration/placement, overlaps, empty dates, navigation/agenda, large text,
  shared-child labels and no writes before edit/save.
- `mobile/integration_test/calendar_grid_scenario_test.dart` registers those same
  prepared journeys on the native engine, with synthetic SQLCipher fixtures.
- Updated existing add-event/child-label journeys for the explicit agenda option
  and the Python runner allowlist regression for the new grid scenario.

## Initial commands and status

| Check | Status |
| --- | --- |
| `flutter pub add kalender:0.33.0` | PASS: resolution completed with three new transitive packages |
| Dart formatting and `flutter analyze` | PASS: no analyzer issues on final implementation |
| `python3 -m unittest discover -s scripts -p 'test_*.py'` | PASS, exit 0 |
| `flutter test --coverage --reporter expanded` | **FAIL, exit 1**; `test-results/bug016-flutter.log` |
| iPhone 18 Pro / iOS 27 simulator: prepared grid integration command | **FAIL, exit 1**; `test-results/bug016-ios.log` |
| Android 15 / API 35 emulator: prepared grid integration command | **FAIL, exit 1**; `test-results/bug016-android.log` |
| Ruff check for changed Python tooling | PASS |
| `python3 scripts/version.py check` | PASS: `0.1.0+1` |
| `git diff --check` | PASS |
| OSV querybatch: Kalender and three new exact dependency versions | No listed vulnerabilities returned |
| Pinned Gitleaks staged secret scan | PASS: no leaks found |

## Follow-up diagnosis and corrections

The initial run had 118 passing and two failing Flutter tests. Each native grid
run had two passing and one failing test. Both failures were test expectations:

- `CAL-GRID-UNIT-002` requested `UTC`, which is absent from the bundled timezone
  dataset. The test now uses the canonical `Etc/UTC` identifier and retains the
  exact `09:30–11:30` conversion assertion and spring DST duration assertions.
- `CAL-GRID-MOB-003` expected `Mia, Jithu`, while the repository explicitly orders
  child profiles by display name. The shared widget/native test now expects
  `Jithu, Mia`; both child labels and the exact event time remain required.

Only these two test expectations changed; application behavior is unchanged.
The stable scenario catalogue records these details. Logs remain ignored local
artifacts under repository `test-results/`.

### Follow-up execution

- Targeted adapter/widget tests: **PASS, 7 tests**;
  `test-results/bug016-targeted-retest.log`.
- `flutter test --coverage --reporter expanded`: **PASS, 120 tests**;
  `test-results/bug016-flutter-retest.log`.
- iPhone 18 Pro / iOS 27 simulator, prepared grid suite: **PASS, 3 tests**;
  `test-results/bug016-ios-retest.log`.
- Android 15 / API 35 emulator, prepared grid suite: **PASS, 3 tests**;
  `test-results/bug016-android-retest.log`.
- `flutter analyze`: **PASS, no issues**;
  `test-results/bug016-analyze-retest.log`.
- Formatting of both changed Dart files, version check (`0.1.0+1`) and
  `git diff --check`: **PASS**.

## Boundaries and remaining work

No backend API/OpenAPI, local/server schema, migration, encryption, key lifecycle
or backup-format changes. Backend/API/migration checks were not executed because
those components are unchanged. Native commands use prepared fixtures and no
production backend, credentials or providers. Shipping app builds were not run
separately; remote CI status is not claimed. The redacted staged secret scan
passed before commit.

Physical phones, VoiceOver/TalkBack, real passkeys/protected storage, provider
delivery and production two-device networking remain unverified. Neither backup
portability direction ran; Android-to-iOS remains explicitly deferred.

BUG-013 parsing/duration editing, BUG-014 Undo, BUG-015 colour assignment and the
High-severity BUG-010 security blocker remain open. No new security guarantee is
claimed from this UI change. BUG-016 is resolved for the implemented presentation
and automated coverage. Physical-device/accessibility checks remain unverified.
Wait for the maintainer to select the next bug; do not move to another bug or
stage automatically.
