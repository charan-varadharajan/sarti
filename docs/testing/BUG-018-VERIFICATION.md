# BUG-018 — Today navigation

Date: 2026-10-13. Resolved for automated scope; physical-iPhone retest pending.

## Behavior and implementation

Maintainer approved fixing the physical-phone report after BUG-019. The existing
Today segment selected day layout while preserving the browsed date; Flutter
also ignored taps when the segment was already selected.

- CalendarController issues a fresh, memory-only navigation request on every
  Today activation. No local mutation callback, reminder or sync write occurs.
- CalendarScreen handles selected Today activation using the standard segmented
  button callback; its controlled selection remains exactly one range.
- FamilyCalendarView consumes the request and jumps to the clock's current
  instant converted into the configured display timezone. It keeps agenda state.
- Week/Month selection preserves normal browsing. The existing Go to today
  toolbar icon returns to the current period without changing those layouts.
- Clock injection provides deterministic fixtures, including UTC date boundaries
  and DST dates. Production defaults to DateTime.now.

No ADR, server API, schema/migration, dependency, encryption or release-version
change. Docs updated: scenario catalog, module catalog, bug/status and changelog.
User's local iOS project/signing/plist changes are not part of this fix.

## Prepared tests

`support/calendar_today_scenarios.dart` provides seven cases, registered by
`calendar_today_test.dart` and the existing native grid entry point:

- `CAL-TODAY-MOB-001`: repeated selected Today, yesterday/tomorrow, narrow phone;
  actual grid/date/event checks, persistent outbox unchanged.
- `CAL-TODAY-MOB-002`: Week/Month away → Today, correct date/events, agenda retained.
- `CAL-TODAY-MOB-003`: toolbar return preserves Week/Month layout.
- `CAL-TODAY-TZ-001`: four fixed UTC instants, Kiritimati/Honolulu date boundaries
  and Vancouver spring/fall DST dates; current display-zone date/range, no writes.

All content/prerequisites are seeded directly, with widget/controller/database
teardown. No PIN, native AI, provider, passkey or real family data is used.

## Executed checks

| Check | Result / ignored log |
| --- | --- |
| Dart formatting | PASS; bug018-format.log, bug018-format-final.log |
| Flutter analysis | PASS; bug018-analyze.log |
| Full Flutter unit/widget suite | PASS: 151 passed, 2 opt-in host skips; bug018-flutter.log |
| iPhone 18 Pro / iOS 27 grid + Today scenarios | PASS: 10 scenarios; bug018-ios.log |
| Android API 35 grid + Today scenarios | PASS: 10 scenarios; bug018-android.log |
| Version integrity 0.1.0+1 / whitespace | PASS |
| Offline staged secret scan | PASS; bug018-secret-scan.log; cached pinned image, no network/mounts, read-only container |

Failure logs are not inspected under the maintainer's current reporting rule.
Native runs execute ten prepared scenarios each (three grid plus seven Today).
Both native commands completed successfully.

## Limits and remaining work

Physical iPhone rebuild/retest, VoiceOver/TalkBack and real OS clock/locale
changes are not executed by these controlled fixtures. Native results do not
prove passkey, provider, push, cloud-AI or physical secure-storage compatibility.
Backend unit/integration/migration/OpenAPI/Docker/dependency checks are not rerun:
no backend, schema, contract or dependency change. Backup portability excluded.
CI result is not inferred from local checks.

Only BUG-018 is implemented here. BUG-020/021 family setup/management and BUG-015
child colours remain pending; BUG-005 broker approval is separate. Stop after
reporting this bug; do not start another automatically.
