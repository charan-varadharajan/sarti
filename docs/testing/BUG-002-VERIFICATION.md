# BUG-002 verification — 2026-10-12

## Result and scope

BUG-002 is resolved in application code and automated tests (commit `cb08bc3`). Owner on phone 1
explicitly generates/saves a recovery phrase and uploads an encrypted snapshot.
An empty phone 2 installation authenticates, discovers/downloads the owner's
snapshot automatically, and requires phrase confirmation before local restore.
There is no required file picker. Login grants download permission, not decryption.
This is not a physical two-phone acceptance claim or Stage 3 acceptance.

## Implementation and approvals

The user approved the v2 key envelope, Sarti-hosted ciphertext retention, UI,
backend/API, and tests. ADR-032 records this approval and supersedes ADR-025's
payload/restore/destination rules; ADR-031 governs the BIP-39 phrase. No dependency
or hosting provider was added. Version remains `0.1.0+1`, with fixes accumulated
under CHANGELOG Unreleased rather than an unrequested release.

Changed areas:

- Mobile: `features/backup/backup_recovery.dart`, `backup_screen.dart`, authenticated
  bootstrap, API client, device-key bootstrap, database path and calendar action.
  Consistent SQLCipher export, authenticated v2 key envelope, family/schema/integrity
  validation, protected activation journal, and refusal to overwrite local data.
- Backend: `api/backups.py`, application routing and table metadata;
  `GET/PUT/DELETE /v1/families/{family_id}/backup`; regenerated OpenAPI.
- Migration `0005`: one bounded opaque blob per family, revision CAS, foreign-key
  cascade and immediate soft-delete purge. Retained until replacement/deletion,
  separate from seven-day sync retention. No local schema change is needed.
- Documentation: ADR/index, architecture/key lifecycle, API/protocol, database/ER
  diagram/migration history, privacy/security/threat model, module catalog,
  operations, status, Stage 3 report, scenario catalog, changelog and defect list.

## Executed checks

| Check | Actual result |
| --- | --- |
| Full Flutter unit/widget suite, with coverage collection | 96 passed |
| Flutter analyzer / Dart formatter | Passed; no analyzer issues |
| Full backend suite with real local PostgreSQL | 22 passed; 88.18% coverage with branch measurement, above 85% gate |
| PostgreSQL migration upgrade/downgrade/re-upgrade | Passed through version 5 |
| Generated OpenAPI contract test | Passed; specification regenerated |
| Ruff format/lint, strict Mypy, Bandit | Passed |
| Runtime pip-audit | No known vulnerabilities |
| Version consistency and script tests | Passed; 3 tests |
| Android debug APK | Built successfully |
| iOS simulator debug, unsigned | Built Runner.app successfully |
| Pinned Gitleaks history scan | History and staged scans: no leaks |
| Current-source Docker API and migrations, cached runtime | Liveness/readiness passed; container healthy; temporary container removed |
| Clean Docker rebuild | Attempted; Docker Hub base-image metadata fetch timed out |

New tests: seven real SQLCipher recovery/storage-failure tests, two prepared-screen
widget journeys, one binary HTTP transport test, one PostgreSQL API integration
journey; migration assertions updated. Existing phrase/envelope tests also ran.
The strengthened event fixture initially missed timezone initialization; the
fixture was corrected and the full suite passed on rerun.

## Security findings and limits

Owner-only full snapshots preserve restricted guardian/resource permissions.
Cross-family/anonymous/revoked access, malformed/legacy/oversized uploads, missing
revision, stale overwrite, wrong phrase, corruption and family mismatch are
rejected. Existing local data and pending activations cannot be overwritten.
Restored events include their recurrence; device identity/session stay fresh.
Old sync keys, cursors, outbox and consent preferences are cleared, preventing
stale keys from being reused as future authorization. Server persistence receives
only opaque ciphertext and bounded metadata; no phrase or key is sent.

Not executed: physical passkey-to-recovery on two phones, production Keychain/
Keystore behavior, OS process-kill recovery, restored reminder delivery,
production TLS/provider backup retention, or live multi-device networking. Native
builds and mocked widget boundaries cannot establish those behaviors. A malicious
server can withhold/replay stored snapshots; time is displayed but is not an
independent cryptographic rollback guarantee. Provider copies require retention
validation before release. Build tooling emits an existing Firebase/Kotlin
migration warning; current Android compilation succeeds.

Future synchronization after restore still requires fresh resource grants, tracked
by BUG-004; BUG-003 child synchronization and BUG-005 optional provider credentials
also remain open. No work on those defects or Stage 4 was started. The next action
is to explain/propose the next defect and wait for explicit user approval.
