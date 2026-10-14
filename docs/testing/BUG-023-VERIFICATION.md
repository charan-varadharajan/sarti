# BUG-023 — Profile navigation and event-entry refinement

Date: 2026-10-14. Development version: 0.5.1+6. Not a public release.

## Delivered

- More and Family hub offer separate People and Pets destinations. People shows
  adult/child profiles, own adult profile, Add child and admin-only Add adult;
  Pets shows pets and admin-only Add pet. Color pickers say Choose color.
- Add adult reuses secure guardian invitations. Guardian management is actionable:
  offline installs explain configured-service requirements, and a configured
  missing/expired session offers explicit passkey sign-in/account creation.
  Authentication returns to the root before opening the authorized guardian
  screen, avoiding edits through an obsolete controller after account binding.
- Blank/whitespace child aliases already generated unique validated aliases;
  helper copy now explains this and regression coverage exercises the UI save.
  Stored aliases stay encrypted and are not exported to cloud requests.
- Event FAB offers Enter event details and Describe an event. Description uses
  the existing native/local fallback and explicit approval path. Read-only and
  recovery entry gates are preserved; no automatic cloud request.
- Shared duration editor shows hours/minutes, preserves exact elapsed minutes,
  rejects negative/invalid remainder, zero and more than seven days. Existing
  one-hour default and explicit DST-duration clarification remain visible.
- Compact end previews respect 12/24-hour preference, add date across midnight
  and zone across a DST-offset change. Start date also uses a readable format.
- Profile editor controllers now wait for route completion before disposal.

## Changed files and governance

Presentation: calendar_screen, family_management_screen, household_profiles_screen,
child_profile_editor, new event_duration_input and guardian_management_action;
AI natural_language_event_dialog and authenticated_calendar_bootstrap.
Tests: new shared profile_navigation_scenarios, existing remaining-bug/adult
scenarios, test harness and bootstrap permission regressions.
Documentation: product adult/pet and Stage 2 flows, module catalog, security model,
stable scenario catalog, BUGS, STATUS, CHANGELOG and canonical version surfaces.

ADRs 022/035/036/038/040 are preserved. No new ADR or approval was needed for
presentation/navigation within approved P0. No endpoint, generated API, database
schema, migration, encryption primitive, key lifecycle or dependency change.
Local SQLCipher v9/PostgreSQL 0010 and current OpenAPI contract remain unchanged.
The maintainer's iOS signing edits are excluded from staging and commit.

## Executed results

| Check | Result |
| --- | --- |
| Full Flutter unit/widget suite | PASS: 221 tests, 2 explicit HTTP host-dependent skips |
| Flutter analysis / formatting | PASS |
| iOS prepared regressions | PASS: 18 checks |
| iOS prepared calendar/setup | PASS: 8 checks |
| iOS prepared adult/profile | PASS: 10 checks |
| Android prepared regressions | PASS: 18 checks |
| Android prepared calendar/setup | PASS: 8 checks |
| Android prepared adult/profile | PASS: 10 checks |
| Backend Ruff format/lint, strict Mypy, Bandit | PASS |
| Backend unit/API contract tests | PASS: 41 tests; 16 integration cases deselected |
| Version integrity | PASS |
| Version/test-runner/CI-runner tooling | PASS: 11 tests |
| Existing local Docker live/ready health | PASS |
| Normal Android debug build | PASS: normal debug APK produced |
| Normal unsigned iOS device debug build | PASS: normal iphoneos Runner.app produced, signing disabled |
| Runtime dependency audit | PASS: pinned runtime requirements, no listed vulnerabilities |
| Staged pinned offline secret scan / diff whitespace | PASS |

Initial failures were inspected only for failed cases: old copy/time expectations,
an overly broad text finder and a fixture property name were corrected. Final
full Flutter/native suites pass. No successful log diagnosis was performed.
Logs are ignored under test-results/bug023-* and dated native runner logs.
Native tests used iPhone 18 Pro/iOS 27 simulator and Android emulator-5554.

## Coverage and limits

Nine new stable scenarios cover separate navigation, nonadmin controls, secure
adult entry, offline guidance, configured missing-session sign-in/cancel,
automatic alias assignment, FAB description, duration validation and end display.
Existing batch-confirmation, DST uncertainty, adult privacy/sharing/crypto,
child/sync/security and recovery tests run in the Flutter regression suite.
Backend unit-only coverage is not a full integration coverage claim.

Physical passkey/sign-in, connected two-phone invitations/removal, native-model
inference, OS reminders and provider delivery are not established by simulator
fixtures. Offline installs still require a configured connected build before
inviting/removing guardians; no service deployment is included. Current live
cloud testing remains explicitly deferred under BUG-005, with broker disabled
by default. Aliases are pseudonyms, not anonymity or proof that family information
never leaves the phone; ADR-036 fresh request labels govern optional cloud input.

The two opt-in HTTP/Dart contracts and PostgreSQL migration/API integration suites
were not rerun: no API/schema/migration/transport implementation changed; their
prior execution is documented separately, not counted here. Cross-platform
backup transfers (including deferred Android→iOS) were not run. CI remote results
remain unverified until the pushed run is observed. No Stage 4 or production
activation is included. Recommended next action: rebuild the connected app for
physical UI acceptance, then complete the existing provider/device release gaps.
