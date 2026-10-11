# Project status

- Current stage: Stage 2 — family calendar and secure synchronization
- Updated: 2026-10-11
- Stage state: implementation complete; local acceptance gates passed

## Delivered

- WebAuthn passkey registration/authentication, hashed sessions, and atomic
  one-active-phone replacement
- Family ownership, child resources, progressive guardian invitations, explicit
  resource permissions, household isolation, revocation, and key-epoch rotation
- SQLCipher-backed family/guardian/child/event/reminder/outbox/conflict schema
- Today/Week/Month UI, child colours, recurring events, pickup assignment,
  cancellation/deletion, and local reminders
- X25519/Ed25519 device keys, XChaCha20-Poly1305 resource operations, signed sealed
  key grants, strict device sequence/replay defense, version vectors, explicit
  conflict resolution, and seven-day ciphertext retention
- Migration `0002`, OpenAPI, ADR-019 through ADR-022, schemas, permissions,
  interaction flows, and security/sync/key documentation

## Local verification

| Check | Result |
| --- | --- |
| Backend Pytest + PostgreSQL integration | 10 passed; 88.28% coverage |
| Alembic upgrade to head | Passed; schema version 2 |
| Ruff / strict Mypy | Passed; 22 source files |
| OpenAPI drift | Passed after regeneration |
| Docker Compose health | Backend and PostgreSQL healthy |
| Flutter format/analyze | Passed; no issues |
| Flutter unit/widget tests | 5 passed |
| Android debug build | Passed; APK produced |
| iOS unsigned debug build | Passed; Runner.app produced |
| Gitleaks working-tree/history scan | Passed; no leaks found |

## Device/platform gaps

- No physical iOS/Android passkey ceremony, biometric secure-storage policy,
  scheduled-notification delivery, or two-device network sync was executed.
- Associated domains/asset links need the production RP domain.
- The in-process encrypted sync simulation validates protocol behavior but does
  not establish provider or OS compatibility.
- Snapshot recovery for a device offline beyond seven days is unresolved; Stage 3
  backup/recovery must define it.

Stage 3 is requested but must receive explicit approval after this Stage 2 report.
