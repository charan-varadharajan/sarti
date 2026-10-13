# BUG-011 — Versioned deterministic sync metadata verification

Date: 2026-10-12. Status: **Targeted Flutter fixes pass; full-suite rerun pending.**

## Approval and implementation

The maintainer approved the versioned deterministic metadata/legacy compatibility
proposal with “ok-fix”. Accepted ADR-034 supersedes only the serialization detail
of ADR-020/021. No new primitive, dependency, service, key custody or UI added.

- `resourceAdditionalData` encodes protocol 2 with fixed top-level fields and
  sorted logical-version keys. Encryption and decryption share it. Protocol 1
  retains existing encoding; unknown versions have no fallback.
- `RelayEnvelope`, saved pending JSON and HTTP transport carry the version.
  New operations use v2; missing version in an existing envelope means v1.
  Accepted pending ciphertext is retried unchanged, never relabeled.
- Backend upload/download models accept versions 1/2 (default legacy 1), persist
  them and include them in exact-retry comparison. OpenAPI regenerated.
- Migration 0006 adds the constrained default-1 tag without changing old
  ciphertext. Downgrade refuses to erase tags while v2 rows remain.
  SQLCipher stays schema v6; its versioned envelope JSON needs no migration.
- Protocol-1 multi-author ciphertext whose original map order is already lost
  cannot be reconstructed safely. Retain ciphertext/local data/cursor and
  recover from authorized snapshot/original author data; never guess/drop it.
- Deploy additive backend/migration before upgraded clients. Old clients cannot
  decode v2; mixed-client concurrent editing requires upgrades.

## Tests added/updated

- `mobile/test/sync_metadata_test.dart`: exact bytes/reordered maps, all metadata
  field tampering and downgrade rejection, exact v1 pending retry, legacy
  decoding and safe handling of irrecoverably reordered legacy AAD.
- `mobile/test/postgres_sync_roundtrip_test.dart`: real Dart encryption, HTTP
  upload/download, PostgreSQL JSONB ordering, independent SQLCipher clients,
  concurrent alternatives, exact retries and explicit resolution/event convergence.
- `backend/tests/integration/test_sync_postgres_mobile.py`: opt-in fixture host
  seeds synthetic identities/membership, starts loopback API, invokes Dart and
  shuts down. No resource key is sent to backend. Passkeys are stubbed.
- `backend/tests/integration/test_sync_protocol.py`: v1/v2 contracts, version
  mismatch/unknown rejection, byte-preserving upgrade and downgrade protection.
- Destructive base-migration test deliberately clears test operations before
  teardown. Memory relay adapters preserve the new version for existing tests.
- Stable AAD-* scenarios are in TEST-SCENARIOS.md. BUG-017 separately records
  remote conflict-card retirement; its behavior was not changed here.

## Initial executed results

Only exit statuses were reviewed. Failure logs were not read, diagnoses were
not attempted and failing checks were not retried. Logs are ignored under
`test-results/bug011-*.log`; no counts are inferred.

| Check | Result |
| --- | --- |
| Isolated `sarti_bug011` PostgreSQL setup | PASS |
| Alembic upgrade head (0006) | PASS; migrations log |
| Full backend Pytest with coverage, unit/integration/security/contracts/migration | PASS; backend log (mobile host skipped without opt-in) |
| Ruff formatting and lint | PASS |
| Strict Mypy and Bandit | PASS |
| Runtime pip-audit | PASS |
| Dart formatting | PASS |
| Flutter analysis | **FAIL**, exit 1; analyze log |
| Full Flutter unit/widget suite with coverage | **FAIL**, exit 1; flutter log (host-dependent case skipped) |
| Explicit HTTP/PostgreSQL/Dart regression host | PASS; http-host and http-mobile logs |
| Docker current-source build/startup | PASS; docker-smoke log |
| Docker live and ready endpoints | PASS |
| Generated OpenAPI, version integrity 0.1.0+1 and whitespace | PASS |
| Cached pinned Gitleaks staged scan (network disabled, read-only, no mounts) | PASS; secret-scan log |

The first host-launch attempt used system Python without SQLAlchemy and exited
before executing any tests. It was invoked with the repository Python environment;
the actual explicit contract check then ran once and passed.

## Authorized spot-fix follow-up

The maintainer authorized extracting only the failure details and fixing them.
Analysis reported one missing-braces style issue in `resourceAdditionalData`;
braces were added without changing encoding. The only failed widget test was
`CAL-MOB-001`, which expected its saved event in today's agenda. The editor's
one-hour-ahead default can fall on tomorrow. The test now navigates at most one
day to the saved event date and asserts that date before the unchanged event,
recurrence, child and reminder assertions. App calendar behavior is unchanged.

- `flutter analyze`: **PASS**, `bug011-spot-analyze.log`.
- Only failed widget test (`flutter test test/foundation_screen_test.dart
  --plain-name CAL-MOB-001 --reporter expanded`): **PASS**,
  `bug011-spot-widget.log`.
- Dart formatting for both edited files and `git diff --check`: **PASS**.
- Full Flutter, backend, real HTTP/PostgreSQL and native suites were not rerun
  in this targeted follow-up. Earlier backend/HTTP successes remain evidence;
  a corrected full-suite pass is not inferred. BUG-011 remains open pending it.

## Limits and remaining action

The identified Flutter failures are corrected and their targeted reruns pass.
A full Flutter suite rerun is still required for closure. No native simulator/emulator suite or store build
was run: no native bridge or UI changed. Neither backup portability direction
ran; Android-to-iOS remains explicitly deferred. Physical passkeys, protected
storage, two physical phones, background delivery and production transport
remain separate checks. Existing legacy map-order loss is not claimed repaired.
No Stage 4 work is included; do not advance to another bug automatically.
