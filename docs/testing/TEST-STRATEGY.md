# Test strategy

## Principles

Tests demonstrate defined behavior at the lowest useful level. Security claims
need negative and abuse-case coverage. Mocks demonstrate application behavior,
not compatibility with devices, operating systems, SDKs, or providers.

Functional journeys and their reusable fixture/entry/teardown contracts are
maintained in [`TEST-SCENARIOS.md`](TEST-SCENARIOS.md). Prerequisite state is
seeded outside the UI unless creation of that state is the behavior under test.

## Suites

| Suite | Purpose | Required when |
| --- | --- | --- |
| Dart unit/widget | Domain, state, validation, and UI behavior | Flutter behavior changes |
| Mobile integration/E2E | SQLCipher, offline flows, native APIs | Cross-layer mobile changes |
| Python unit | Backend domain and application behavior | Backend behavior changes |
| API integration/contract | Auth, validation, errors, idempotency, OpenAPI | Endpoint changes |
| PostgreSQL migration | Upgrade, rollback policy, constraints, retention | Server schema changes |
| SQLite migration | Upgrade, interruption recovery, encryption | Local schema changes |
| Security | Isolation, authorization, keys, disclosure, abuse | Security boundary changes |
| Sync simulation | Offline, duplicate, reorder, conflict, convergence | Sync changes |
| Smoke | Critical startup and user journey | Every releasable build |

Regression coverage accompanies bug fixes. Every change records categories that
are not applicable with a reason in its completion report.

ADR-033/BUG-016 adds a read-only Kalender presentation adapter and prepared
day/week/month scenarios shared by widget and native suites. Adapter regressions
cover overnight carry-in, elapsed duration across DST, recurrence, display zones,
family/resource scope and removal/cancellation filtering. Grid scenarios cover
relative event placement/duration, overlaps, empty dates, range navigation,
agenda/large-text reading and navigation without outbox mutations. Tests run
with saved logs; the assistant reports status without failure diagnosis unless
the maintainer requests it. Current results are in BUG-016-VERIFICATION.md;
a failed suite keeps BUG-016 open. Native scenarios remain absent from CI
(BUG-012). No backup portability scenario is included in the grid suite.

## Mandatory scenarios

- Two families cannot read or mutate each other's metadata or ciphertext.
- Inactive and replaced phones cannot obtain new relay data.
- Relay items expire after seven days and cleanup is retry safe.
- Offline operations survive restart and converge after reconnection.
- Duplicate, reordered, malformed, replayed, and tampered sync input is safe.
- AI suggestions cannot mutate state before explicit confirmation.
- Deterministic fallback works when native AI is absent or fails.
- Native model output cannot replace fields the deterministic parser resolved.
- Malformed native output is rejected without leaking prompt or response data.
- Cloud AI defaults off, requires explicit versioned consent, and can be disabled.
- Email content cannot override parser policy or cause automatic mutations.
- Email plaintext is absent from PostgreSQL; delivery is sealed separately to
  active devices, malformed ciphertext is discarded, and dismissal is scoped to
  the authenticated recipient device.
- Logs, URLs, crash data, and push payloads contain no sensitive content.
- Push clients reject payloads containing fields beyond the exact opaque
  `{"type":"sync_available"}` shape, register token rotation, coalesce duplicate
  wake-ups, and catch up on foreground transition.
- Backup restore detects corruption and requires valid recovery material.

## Automated gates through Stage 2

- Python: Ruff format/lint, strict Mypy, Bandit, pip-audit, Pytest with branch
  coverage, API/OpenAPI contract, PostgreSQL migration, and tenant/error tests.
- Flutter: Dart format, Flutter analyze, widget/unit tests, real SQLCipher engine
  check, Android debug build, and unsigned iOS debug build.
- Repository: Docker health smoke, Gitleaks secret scan, Dependabot, and pull
  request dependency review at high severity.
- Contract drift: generated FastAPI OpenAPI must equal `backend/openapi.json`.

Stage 2 adds a real PostgreSQL API journey covering passkey ceremony boundaries,
device replacement, two-family isolation, invitation acceptance/approval,
permission-scoped sealed grants, duplicate/replayed/malformed envelopes, expiry,
revocation, and epoch rotation. Dart tests cover encrypted offline writes,
XChaCha20-Poly1305 relay simulation, duplicate prevention, concurrent-edit
preservation/resolution, recurrence across DST, progressive onboarding, child
assignment, and reminder scheduling invocation.

Mocks establish application behavior only. Real passkey ceremonies, Keychain and
Keystore biometric policies, notification delivery, process-kill persistence,
and multi-device networking need physical-device/provider validation.

ADR-029 adds native-bridge unit tests and an end-to-end widget path that enters a
sentence, reviews a proposal, confirms it, verifies the child assignment, and
undoes the event. Native iOS and Android compilation are build gates. A release
still requires successful inference and offline/failure behavior on eligible
physical devices; mocked channels and simulators cannot establish those facts.

Push coordinator tests establish application behavior only. A release requires
two physical devices to verify FCM/APNs token registration, delayed/coalesced
delivery, revoked-device behavior, process suspension, and encrypted convergence
with production-equivalent provider configuration.

Authenticated runtime tests cover serialized retry, client-ID family
provisioning, wake-up after upload, session expiry, and email refresh. The email
widget path decrypts a sealed delivery, displays source attribution, proves no
event exists before approval, then saves and dismisses after approval. These
tests do not establish Cloudflare, Firebase, or physical-device compatibility.

ADR-032 backup checks combine real SQLCipher snapshots of prepared recurring
calendar events with an independent empty replacement installation. Tests verify
key recovery, family scope, wrong phrases, corruption, preservation of existing
local data, protected-storage failures, pending activation retries, and fresh
device identity. Binary transport and real PostgreSQL API tests verify owner/
tenant/device isolation, bounded uploads, stale revisions, and deletion purge.
Direct backup-screen widget fixtures require explicit phrase acknowledgement and
restore confirmation. Physical passkey-to-recovery and OS interruption/reminder
behavior remain release checks; these are not established by widget mocks.

`BACKUP-XPLAT-001` executes the backup/restore screen against native SQLCipher
and libsodium on an iOS simulator and a separate Android emulator. A host runner
transfers only the newly created `.srtbk`, compares exact bytes/digest, and waits
for live-app acknowledgements before Flutter removes either test app. Fixture
credentials and secret-store adapter are synthetic; this test establishes file
portability, not passkey, production transport or hardware-backed storage.
See [execution instructions/results](BACKUP-PORTABILITY.md).

`BACKUP-XPLAT-002` reverses the same prepared native journey (Android exporter,
iOS restorer). Select `--direction android-to-ios`. It is currently added but
not executed at the user's request; the shared assertions do not establish
reverse-direction compatibility until that scenario runs.

BUG-003 adds prepared owner/guardian devices with separate SQLCipher databases
and real libsodium keys. `CHILD-SYNC-*`, `CHILD-SEC-*`, `CHILD-MIG-001` and
`CHILD-MOB-*` cover encrypted child creation, grants, offline/retry/rotation,
resource separation, scope/tamper/revocation and receiving UI labels/colours.
A loopback HTTP contract test checks metadata-only resource requests and signed
sealed-key transport. Real PostgreSQL tests exercise explicit sharing consent,
isolation, filtered paging, grant uniqueness, current authorization and epoch
initialization. `CHILD-NATIVE-001` repeats the prepared UI journey on each native
platform with two logical devices and a controlled relay; it does not establish
physical cross-phone transport. See `BUG-003-VERIFICATION.md` for exact results.

ADR-034/BUG-011 adds exact metadata byte vectors, all-field tampering,
legacy-envelope retry/decoding, unchanged migration ciphertext and version-aware
idempotency tests. The explicit loopback HTTP/PostgreSQL/Dart host executes
multi-author JSONB reordering with actual libsodium and SQLCipher, keeps both
conflict alternatives and verifies event convergence after explicit resolution.
It is opt-in (`SARTI_RUN_MOBILE_CONTRACT=1`); default Flutter/backend runs skip
that host-dependent test. Current results: `BUG-011-VERIFICATION.md`.

ADR-035/BUG-004 adds GUARD-* prepared widget/native and unit cases for
share/copy/QR, pending isolation, matching device code, permission-scoped initial
state, interrupted retries and removal. The explicit HTTP/PostgreSQL/Dart host
uses actual crypto/key transport and expires retained relay fixtures to require
fresh handoff. Backend abuse tests cover expiry, replay, cancellation, stale
pins, resource scope and quotas. Native share/clipboard are injected to avoid
sending messages; physical OS camera/link/provider behavior remains unverified.
Results are recorded in BUG-004-VERIFICATION.md after execution.

ADR-039 adds RETENTION-* prepared settings/unit/native, API authorization,
SQLCipher/PostgreSQL migration and encrypted two-device convergence scenarios.
Scope/clock/recurrence/conflict assertions run without UI prerequisite creation.
`./test --ios --scenario retention` and Android counterpart select the native
journeys. Family recovery continuation remains blocked by BUG-022 rather than
being inferred from the automatic-cleanup pause test. Results: ADR-039-VERIFICATION.md.

Family recovery continuation has prepared real SQLCipher/libsodium fixtures with
direct recovery-screen entry, synthetic fault injection and a real
HTTP/PostgreSQL replacement-device journey (WebAuthn stub explicitly scoped).
Run `./test --ios --scenario recovery` or Android equivalent for same-platform
native recovery; this does not run deferred Android→iOS portability. Results and
security coverage: BUG-022-VERIFICATION.md.

BUG-012 adds native iOS journeys to main/PR CI using available simulator discovery,
allowlisted prepared fixtures, per-scenario pass/fail summary and retained failure
logs/screenshots. The exact runner is also executed locally; local passes do not
claim the remote macOS job passed. See REMAINING-BUGS-VERIFICATION.md.
