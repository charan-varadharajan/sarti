# ADR-033: Kalender calendar presentation

- Status: Accepted
- Date: 2026-10-12
- Approval: Maintainer explicitly selected Kalender for BUG-016 and authorized
  its implementation. No earlier ADR is superseded.

## Decision

Use `kalender` 0.33.0, pinned exactly, for day/week time grids and the month grid.
Keep the presentation adapter in `features/calendar/presentation`. The existing
SQLCipher repository, calendar controller, recurrence engine and resource/sync
protocol remain authoritative. Convert domain occurrences to UTC start/end
display objects and provide the user's IANA display timezone to Kalender.

The adapter includes occurrences beginning before the visible range whose
durations overlap it, and excludes other family/resource scopes, tombstones and
cancelled events. Duration is elapsed minutes; recurrence remains civil-time
based under ADR-022. Distinct offsets are included in time labels across DST.

Disable package event creation, dragging and resizing. Tapping an event opens
Sarti's existing editor; display/navigation cannot write to the repository.
Keep an agenda toggle for accessible reading and existing cancel/delete actions.
Seven-day week columns scroll horizontally on narrow phones. Month includes a
selected-day agenda; day/week grids remain available when empty.

## Dependency review

The official release requires Dart >=3.10 and Flutter >=3.38.1, compatible with
Sarti's pinned SDKs. Package metadata and the downloaded LICENSE were reviewed.
Kalender is MIT; new resolved dependencies are `linked_pageview` 1.1.5
(Apache-2.0), `scrollable_positioned_list` 0.3.8 (BSD-3-Clause), and
`universal_platform` 1.1.0 (MIT). Existing collection/intl/meta/timezone packages
are reused. `mobile/pubspec.lock` records all resolved versions and checksums.
Flutter's license registry includes package license notices in distributions.

Review of the UI/adapter source found no network, telemetry or persistence path
for calendar content. `universal_platform` reads platform information through
`dart:io`; this does not introduce a network service. OSV querybatch returned no
listed vulnerabilities for these four exact versions on 2026-10-12. This is not
a guarantee of absence of defects. Upstream is pre-1.0 and explicitly allows
breaking minor updates; upgrades require review and regression checks.

Sources: [release](https://pub.dev/packages/kalender/versions/0.33.0),
[repository](https://github.com/werner-scholtz/kalender),
[OSV API](https://google.github.io/osv.dev/api/).

## Verification and limits

Prepared grid widget/native scenarios and adapter DST/overnight/isolation
regressions accompany integration. Results live in
`docs/testing/BUG-016-VERIFICATION.md`. Physical-device and screen-reader
validation remain distinct checks; SDK/platform listings are not test evidence.
BUG-013/014/015 and the existing release blockers remain separate work.
No server API, database schema, backup format or encryption change is required.
