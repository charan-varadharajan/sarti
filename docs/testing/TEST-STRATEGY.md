# Test strategy

## Principles

Tests demonstrate defined behavior at the lowest useful level. Security claims
need negative and abuse-case coverage. Mocks demonstrate application behavior,
not compatibility with devices, operating systems, SDKs, or providers.

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
