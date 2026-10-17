# Stage 5 — Implementation progress report

Date: 2026-10-16. ADR-041 accepted by maintainer; Stage 5 incomplete.

## Implemented foundation

- Contact-free registration retained; authenticator labels now role-neutral.
- Current-phone WebAuthn step-up with scoped/session-bound five-minute single-use
  proof, strict validation, hashed persistence and no phone/session replacement.
- Typed household/classroom/activity/school context and scoped role APIs; explicit
  grants, recipient-device pinning, current ACL revision, multi-admin and concurrent
  last-admin safeguards, readonly caregiver restrictions, expiry/epoch rotation.
- Transactional expiry/audit/confirmation maintenance command with aggregate-only
  output; production scheduling remains deferred.
- Atomic ciphertext audit with authoritative bounded outcome; scoped directory
  and resource discovery. No server audit decryption key.
- Optional recovery onboarding entry, two random word confirmations before upload.
- Pinned local household/private/recovery state; device-wide serialized upload
  sequence and exact interrupted envelope retry across contexts.
- Encrypted-copy household export strips foreign contexts and excluded private
  resources; live store preserved. Partial administrators denied whole-family
  server backup access. Import into occupied local state still fails safely.

## Changed files, APIs and migrations

Backend identity/auth/context/household/sync/backup/expiry/schema modules, new
integration/unit/security tests, generated OpenAPI; Flutter database/repository/
recovery/sync/API/onboarding/backup modules, unit/widget and prepared-native
foundation tests; shared native allowlist/tooling tests; architecture/API/database/
testing/status/changelog documentation. Local signing edits remain separate.

PostgreSQL 0011 (confirmation/ACL revision), 0012 (typed scoped roles and explicit
legacy-owner grant migration), 0013 (scoped resources/encrypted audit); local v10
(composite private calendars/device counter). Existing ciphertext and pending
retry bytes retained. Rollback refuses permission escalation or lost scoped data.
See api/SCOPED-ADMINISTRATION.md and database documentation for exact contracts.

## Tests and acceptance evidence

Baseline: Flutter 221 pass/2 opt-in skips; backend 57 pass with real PostgreSQL,
both HTTP/Dart hosts, 91% reported coverage; previous schema0010. New current
Flutter suite: 229 pass/2 host-dependent skips; both skipped host contracts
executed through the backend suite. Backend: 93 pass with isolated PostgreSQL and
both HTTP/Dart hosts. iOS and Android: 82 checks across nine registered journeys
pass on each platform. Analysis, APK/unsigned iOS builds, migrations/OpenAPI,
Ruff/Mypy/Bandit, Docker live/ready/maintenance smoke, tooling (11 tests), version,
pip-audit, locked Dart dependency advisory check and offline pinned Gitleaks pass.
Remote CI workflow execution remains unverified until a pushed run; local passing
checks do not prove the Linux CI emulator setup. Synthetic WebAuthn verifier fixtures do not prove physical
passkey/protected-storage compatibility. Real libsodium and SQLCipher are used
for content/envelope/snapshot isolation tests.

Deferred: live Gemini/provider activation, Android→iPhone BACKUP-XPLAT-002,
production hosting and physical provider/device acceptance. No cloud call or new
service/dependency is introduced.

## Remaining Stage 5 work / risks

Shipping multi-household selector/runtime/enrollment; caregiver reviewed encrypted
copies; scoped import preserving occupied stores/unsent work; administration
step-up/audit UI and legacy sensitive mutation safeguards; assisted-family recovery
journey; scoped account/context closure/purge; encrypted authorized export step-up;
retention-aware manual deletion/restore and full requirements traceability.
Current new API is not a claim that legacy routes enforce operation-bound proof.
Do not claim full E2EE role management, 30-day restoration or Stage 5 completion.
Previously downloaded content/external backups cannot be remotely erased.

Next is remaining authorized Stage 5 implementation and acceptance. Stage 6 and
hosting remain excluded. ADR-041 approval is already granted; no repeat approval
is required unless the accepted design materially changes.

## Implementation file manifest

Stage 5 foundation changes in this commit; local iOS signing files excluded.

```text
.github/workflows/ci.yml
BUILD_NUMBER
CHANGELOG.md
VERSION
backend/alembic/versions/0011_sensitive_step_up.py
backend/alembic/versions/0012_scoped_context_roles.py
backend/alembic/versions/0013_context_audit.py
backend/openapi.json
backend/src/sarti_backend/__init__.py
backend/src/sarti_backend/api/auth.py
backend/src/sarti_backend/api/backups.py
backend/src/sarti_backend/api/contexts.py
backend/src/sarti_backend/api/households.py
backend/src/sarti_backend/api/step_up.py
backend/src/sarti_backend/api/sync.py
backend/src/sarti_backend/core/auth.py
backend/src/sarti_backend/db/schema.py
backend/src/sarti_backend/households/authorization.py
backend/src/sarti_backend/households/expiry.py
backend/src/sarti_backend/households/maintenance.py
backend/src/sarti_backend/households/roles.py
backend/src/sarti_backend/identity/step_up.py
backend/src/sarti_backend/identity/webauthn_service.py
backend/src/sarti_backend/main.py
backend/src/sarti_backend/sync/envelope.py
backend/tests/integration/test_context_administration.py
backend/tests/integration/test_guardian_onboarding_api.py
backend/tests/integration/test_postgres.py
backend/tests/integration/test_retention_migration.py
backend/tests/integration/test_sensitive_step_up.py
backend/tests/unit/test_email_push.py
backend/tests/unit/test_scoped_roles.py
docs/STAGE-5-REPORT.md
docs/STATUS.md
docs/api/SCOPED-ADMINISTRATION.md
docs/architecture/ADR-INDEX.md
docs/architecture/ARCHITECTURE.md
docs/architecture/KEY-MANAGEMENT.md
docs/architecture/adr/041-stage5-scoped-membership-and-sensitive-operations.md
docs/database/DATABASE.md
docs/database/LOCAL-DATABASE.md
docs/database/SERVER-DATABASE.md
docs/engineering/BUGS.md
docs/modules/MODULES.md
docs/operations/OPERATIONS.md
docs/product/P1-BACKLOG.md
docs/product/STAGE-5-GAP-ANALYSIS.md
docs/security/SECURITY-MODEL.md
docs/security/THREAT-MODEL.md
docs/testing/STAGE-5-TEST-PLAN.md
docs/testing/TEST-SCENARIOS.md
docs/testing/TEST-STRATEGY.md
mobile/integration_test/backup_portability_test.dart
mobile/integration_test/stage5_foundation_scenario_test.dart
mobile/lib/src/core/database/sarti_database.dart
mobile/lib/src/core/network/sarti_api.dart
mobile/lib/src/features/backup/backup_recovery.dart
mobile/lib/src/features/backup/backup_screen.dart
mobile/lib/src/features/backup/recovery_phrase_confirmation.dart
mobile/lib/src/features/calendar/data/calendar_recovery_store.dart
mobile/lib/src/features/calendar/data/calendar_repository.dart
mobile/lib/src/features/calendar/presentation/calendar_screen.dart
mobile/lib/src/features/calendar/presentation/family_setup_screen.dart
mobile/lib/src/features/sync/authenticated_calendar_bootstrap.dart
mobile/lib/src/features/sync/resource_key_sync.dart
mobile/lib/src/features/sync/sync_engine.dart
mobile/pubspec.yaml
mobile/test/backup_screen_test.dart
mobile/test/bootstrap_permission_refresh_test.dart
mobile/test/family_recovery_continuation_test.dart
mobile/test/multi_household_state_test.dart
mobile/test/recovery_migration_test.dart
mobile/test/recovery_phrase_confirmation_test.dart
mobile/test/sensitive_action_api_test.dart
mobile/test/support/recovery_confirmation_helper.dart
scripts/run_tests.py
scripts/test_run_tests.py
```
