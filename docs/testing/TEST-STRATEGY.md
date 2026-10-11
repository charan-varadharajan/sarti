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

## Quality gates

CI will eventually require formatting, static analysis, unit and integration
tests, generated OpenAPI drift detection, migration verification, dependency
review, vulnerability scanning, secret scanning, and build smoke tests. Exact
tools are selected alongside the initial code scaffolds and documented before
they become required.

## Stage 1 applicability

Stage 1 changes documentation only. Automated code, API, migration, security, and
UI suites are not applicable because no implementation, dependency, schema, or
executable contract exists. Documentation links and repository consistency are
checked manually in this stage.
