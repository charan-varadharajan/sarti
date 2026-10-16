# Stage 5 — Requirements-to-tests traceability

Date: 2026-10-16. Product scope authorized by maintainer; ADR-041 proposed.
New S5-* scenarios below are planned, not implemented/executed. Existing baseline
results are in ../product/STAGE-5-GAP-ANALYSIS.md; they prove existing behavior only.

| Contract case | Stable scenario | Existing reusable evidence | Required new coverage/layers |
| --- | --- | --- | --- |
| 1. Contact-free registration | S5-ACCOUNT-001 | test_stage2_api.py; auth schema has no contact fields | Neutral account onboarding without personal information; API/schema/SQL metadata and widget/native flow |
| 2. Passkey/device authorization | S5-AUTH-001 | stage2 API; native adapter/device store | Native boundary and real verifier vectors; actual platform ceremony separately; active device and wrong RP/origin/user-verification rejection |
| 3. Duplicate account/device registration | S5-ACCOUNT-002 | Credential PK, challenge replay, active-device index | Duplicate credentials, concurrent completion, reused/expired/malformed challenge, retry atomicity; no orphan account/device/session; define key reuse policy |
| 4. Recovery/invalid attempts | S5-RECOVERY-001 | backup_service_test, backup_recovery_test; existing recovery scenarios | Onboarding word confirmation/skip/interruption, wrong phrase/identity/scope, corruption, audit and no private bypass |
| 5. Replacement authorization | S5-DEVICE-001 | test_device_replacement.py | Multi-context replacement with fresh grants; current-device step-up does not replace itself; interrupted transition rollback |
| 6. Old-device revocation | S5-DEVICE-002 | replacement concurrency/API tests | Old sessions/uploads/reads/grants/push/email/exports denied across all authorized contexts; previously downloaded copies explicitly outside erasure claim |
| 7. Multiple administrators | S5-ADMIN-001 | owner/guardian authorization foundation | Promotion/demotion, step-up, no private escalation, simultaneous last-admin removals/self-leave/account delete prevented; SQL/API/widget/native |
| 8. Multiple households/adult | S5-HOUSEHOLD-001 | Backend composite membership PK | A/B switch/query/write/cursor/reminder/recovery/private resource isolation, global device upload sequence, stale editor and async cancellation; offline reconnect/native |
| 9. Multiple households/child | S5-CHILD-001 | child resource keys/profile fixtures | Independent scoped representations, explicit separate consent, no global directory/implicit copy, remove in A preserves B; SQL/API/crypto/UI |
| 10. Child permissions | S5-PERMISSION-001 | test_child_sync_api.py; CHILD-SEC-* | Narrow/widen/read/write/admin/grant changes, fresh consent and rotation, private data and other-child scheduling excluded; stale authorization rejected |
| 11. Limited caregiver | S5-CAREGIVER-001 | Resource ACL/sodium/relay fixtures | Scoped copies not whole-calendar key, read-only/expiry/no source overwrite, title/notes/other-child leakage negatives; API/SQL/crypto/UI/native |
| 12. Invitation expiry/replay/revoke | S5-INVITE-001 | guardian_onboarding_test and real guardian HTTP host | Each context/role, superseded/expired/cancelled token, changed device/fingerprint, duplicate approval and quota, no pending keys; QR/native separate from message delivery |
| 13. Unauthorized role escalation | S5-ROLE-001 | require_resource_permission / permission matrix | Role/action/context matrix all roles; teacher/school/volunteer cannot gain household/private rights; expired grants, forged scope, step-up replay/target changes; parameterized unit/API/security |
| 14. Cross-household isolation | S5-ISOLATION-001 | Two-family PostgreSQL/crypto tests | Every route/list/directory/grant/backup/audit/export/recovery, empty results and missing IDs; account switch, child links and local DB queries; no UI-only isolation |
| 15. Key rotation | S5-KEY-001 | CHILD-SYNC/security and device replacement | Removal/demotion/expiry/narrowing rotates exactly affected scopes; concurrent grants/current-epoch/revoked granter, retries and pending-envelope preservation; unrelated household unchanged |
| 16. Deletion/export | S5-DELETE-001 | Existing snapshot/purge hooks; not complete workflow | Account/family closure, last-admin, confirmation/step-up, idempotency/partial failures, ciphertext/usage/email/audit purge, authorized scoped export excludes private/ungranted/other contexts; retention/trash restore boundaries |
| 17. Offline recovery/sync | S5-OFFLINE-001 | RECOVERY-CONT, outbox/conflicts, HTTP/Dart hosts | Multi-household offline edits/switch/reconnect, scoped snapshot import preserving unrelated unsent work, assisted grants, duplicate/reorder/conflict, expired history and server-unavailable failure behavior |

Auxiliary S5-AUDIT-001 covers atomic sensitive-action/audit commit, authorized
ciphertext-only access, forged client narration, outcome binding, no sensitive
logging, audit retention and closure purge. S5-RESTORE-001 covers restore at
29/30-day boundaries, earlier calendar retention, explicit permanent deletion,
wrong/private/foreign resource, stale snapshot/replay, clock uncertainty and
current-epoch authorized causal restoration. No event may be silently resurrected.

## Fixtures, automation and acceptance

Seed synthetic accounts A/B/C, family A/B, administrator/guardian/caregiver roles,
school/classroom/activity scopes and separate real libsodium/SQLCipher state.
Use direct target-screen/intent entry. Create prerequisites through UI only when
registration/invitation/setup itself is the behavior under test. Use isolated
PostgreSQL and migration fixtures; never development families or real private data.
Destroy fixtures and encrypted temporary stores after each test. Capture synthetic
canaries to assert absence from server rows/logs/errors/URLs/push/artifacts.

Implement pure policy unit tests, API/real-PostgreSQL integration, native-to-Flutter
and generated OpenAPI contracts, security tests, encrypted
migration preservation/rollback, widget/prepared native E2E, Docker health/build
smoke, dependency/static/secret/version/tooling gates. Add tests to default suites
and native allowlist/CI; do not count a planned ID or mock-only result as coverage.

Run full automated code-change gates under TEST-STRATEGY.md on final source,
including both enabled existing HTTP/Dart hosts, all registered native iOS/Android
journeys and new S5-* cases, normal app builds and database migration/security
regression. Inspect failed cases only under current maintainer authorization,
fix failures and rerun final affected gates; report counts, skips and incomplete
coverage accurately. Real platform passkeys, protected storage, phone replacement,
QR/share delivery and provider/OS behavior require physical acceptance separately.

No cloud/hosting activation, live Gemini call or unapproved Android-to-iPhone
backup portability run is included. Hosting stays last; no Stage 6 automatically.

## Baseline vs completion

Baseline executed before runtime changes: Flutter 221 pass/2 host-dependent skips
(both hosts run through backend), backend 57 pass with real PostgreSQL and both
cross-layer hosts, analysis/static/security/tooling/version checks pass. Native
journeys/builds/providers were not rerun for this documentation-only assessment.
Full Stage 5 acceptance cannot be marked complete until the new scenarios above
exist and pass, required gates run and any physical/provider limits are explicit.
