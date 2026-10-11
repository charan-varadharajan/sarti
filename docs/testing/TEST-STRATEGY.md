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
- Email content cannot override parser policy or cause automatic mutations.
- Logs, URLs, crash data, and push payloads contain no sensitive content.
- Backup restore detects corruption and requires valid recovery material.

## Stage 1 automated gates

- Python: Ruff format/lint, strict Mypy, Bandit, pip-audit, Pytest with branch
  coverage, API/OpenAPI contract, PostgreSQL migration, and tenant/error tests.
- Flutter: Dart format, Flutter analyze, widget/unit tests, real SQLCipher engine
  check, Android debug build, and unsigned iOS debug build.
- Repository: Docker health smoke, Gitleaks secret scan, Dependabot, and pull
  request dependency review at high severity.
- Contract drift: generated FastAPI OpenAPI must equal `backend/openapi.json`.

The Stage 1 tenant test exercises reusable fail-closed infrastructure; there are
no protected resource endpoints yet. Sync, AI, email, passkey, authorization,
backup, local migration, device, export/deletion, and end-to-end tests are not
applicable because those behaviors are deliberately unimplemented.
