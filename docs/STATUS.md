# Project status

- Current stage: Stage 3 — AI proposals, email intake, push notifications, and backup/recovery
- Updated: 2026-10-12
- Stage state: audit failed; remediation required before Stage 3 acceptance

## Stage 3 verification audit (2026-10-11)

The local mechanical gates pass after repairing the migration assertion,
resolved Firebase dependency locks, backend formatting/lint findings, a calendar
timezone round-trip regression, and two documented Gitleaks false positives.
Stage 3 remains incomplete because:

- the Gemini adapter sends natural-language family input to cloud inference,
  contrary to the on-device-only contract;
- the server persists email sender, subject, and body as plaintext and has no
  authorized-device encrypted delivery path or retention cleanup job;
- the shipping mobile app still boots the Stage 2 calendar and does not expose
  the proposal/confirmation, email suggestion, push registration, or backup and
  restore flows;
- quiet hours and the documented Firebase Messaging client integration are not
  implemented;
- the recovery phrase uses a 256-word subset without the BIP-39 checksum and is
  therefore not a BIP-39 mnemonic; and
- real provider and physical-device acceptance tests remain unexecuted.

## Approved beta hosting

ADR-027 selects Google Cloud Run plus Neon Free for development and the initial
private beta. Production hosting remains unresolved pending Stage 3 remediation,
backup/recovery validation, provider review, and an explicit production decision.

## Delivered

### Stage 2
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

### Stage 3
- Deterministic NLP event parser (title, time, date, recurrence, location, name
  tokens); never fabricates; 30 unit tests
- Gemini cloud assist adapter (raw text only, no family context, additive-only
  merge with deterministic result, never throws); ADR-023
- Cloudflare Email Routing → `POST /v1/email/ingest` webhook: HMAC worker-secret
  auth, prompt-injection sanitization, family-token resolution, 20 emails/family/day
  rate limit, content-digest deduplication, 7-day TTL; ADR-024
- FCM push: `POST /v1/push/register` stores token, `POST /v1/push/wake-up` sends
  opaque `{"type":"sync_available"}` to family devices; ADR-026
- PBKDF2-HMAC-SHA256 (200 k iterations) + XChaCha20-Poly1305 backup with 12-word
  BIP-39 recovery phrase; 11 unit tests; ADR-025
- Migration `0003` (`fcm_token` on devices, `email_token_digest` on families,
  `email_suggestions` table), OpenAPI regenerated, `firebase-admin` dependency added
- ADR-023 through ADR-026 written and approved before implementation

## Local verification

| Check | Result |
| --- | --- |
| Backend Pytest unit + PostgreSQL integration | 19 passed; 87.47% branch coverage |
| Alembic upgrade to head | Passed; schema version 3 |
| Ruff / strict Mypy | Passed |
| OpenAPI drift | Passed after regeneration |
| Docker Compose health | Backend and PostgreSQL healthy |
| Flutter format/analyze | Passed; no issues |
| Flutter unit/widget tests | 46 passed (30 parser + 11 backup + 5 Stage 2) |
| Android debug build | Passed; APK produced |
| iOS unsigned debug build | Passed; Runner.app produced |
| Gitleaks working-tree/history scan | Passed; no leaks found |
| Pip-audit runtime dependency scan | Passed; no known vulnerabilities found |

## Device/platform gaps

- No physical iOS/Android passkey ceremony, biometric secure-storage policy,
  scheduled-notification delivery, or two-device network sync was executed.
- Associated domains/asset links need the production RP domain.
- The in-process encrypted sync simulation validates protocol behavior but does
  not establish provider or OS compatibility.
- Snapshot recovery for a device offline beyond seven days requires a full backup
  restore via the 12-word recovery phrase (ADR-025).
- FCM delivery and Cloudflare Worker integration require production credentials
  and have not been exercised end-to-end.
- Gemini cloud assist requires a production API key; the adapter is wired but
  not exercised against the live API.
