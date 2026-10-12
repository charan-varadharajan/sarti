# Stage 3 completion report

- Stage: Stage 3 — AI proposals, email intake, push notifications, and backup/recovery
- Date: 2026-10-12
- State: audit failed; remediation required before acceptance

## Post-implementation audit (2026-10-11)

The original completion claim below is retained as implementation history, but
it is superseded by this audit. The full local suite passes after targeted build
and test-infrastructure repairs: 19 backend tests at 87.47% branch coverage, 46
Flutter tests, Ruff, Mypy, Bandit, Flutter analyze, Android and unsigned iOS
builds, Docker health and migration 0003, pip-audit, OpenAPI drift, and Gitleaks.

Stage 3 acceptance is blocked by the cloud AI privacy violation, plaintext email
persistence, missing encrypted email delivery and approval flow, missing mobile
integration for Stage 3 features, missing application quiet hours, inaccurate
BIP-39 claims, and unexecuted provider/physical-device tests. The detailed,
current list is maintained in `docs/STATUS.md`.

---

## Features delivered

### Deterministic NLP event parser (ADR-023)
`DeterministicEventParser` implementing the `AiProvider` interface. Parses title,
12h/24h/bare time, today/tomorrow/weekday date, daily/weekly/monthly recurrence,
location (`in`/`at` proper noun), and child/guardian name tokens. Never fabricates
missing fields. `EventProposal` model with `isActionable` and `toRecurrenceRule()`.

### Gemini cloud assist adapter (ADR-023)
`GeminiAiProvider` wrapping `google_generative_ai 0.4.7`. Sends raw input text
only — no family IDs, child names, or profile data. Structured JSON output.
Additive-only merge with the deterministic result. Never throws; returns the
deterministic result on any failure.

### Inbound email gateway (ADR-024)
`POST /v1/email/ingest` — Cloudflare Worker webhook. HMAC constant-time
`X-Worker-Secret` authentication. `<INPUT>` tag injection sanitization on subject
and body. Family token resolved to family ID via SHA-256 digest; unknown token
returns 404. Rate limited to 20 emails per family per 24 hours via COUNT subquery.
Content-digest deduplication returns existing suggestion ID on repeat. Suggestions
stored with 7-day TTL. Raw email never persisted.

### Push notifications (ADR-026)
`POST /v1/push/register` — stores FCM token for the authenticated device.
`POST /v1/push/wake-up` — verifies active membership, sends
`{"type": "sync_available"}` to all other active family devices via
`firebase_admin`. No family content in FCM payload. Returns `dispatched: 0`
gracefully when `fcm_credentials_file` is not configured.

### Backup and recovery (ADR-025)
`BackupService` with `generateRecoveryPhrase()` (12-word BIP-39),
`deriveKey()` (PBKDF2-HMAC-SHA256, 200 k iterations, 32-byte salt),
`createBackup()` (magic header + version + salt + nonce + XChaCha20-Poly1305
ciphertext), `restoreBackup()` (wrong phrase and corrupted data both fail with
`BackupException`). `sodium` is a required parameter to avoid `FutureOr<Sodium>`
type errors.

---

## Changed files

| File | Change |
| --- | --- |
| `mobile/pubspec.yaml` | Added `google_generative_ai: 0.4.7` |
| `mobile/lib/src/features/ai/event_parser.dart` | New — deterministic parser |
| `mobile/lib/src/features/ai/gemini_ai_provider.dart` | New — Gemini adapter |
| `mobile/lib/src/core/backup/backup_service.dart` | New — backup/recovery service |
| `mobile/test/event_parser_test.dart` | New — 30 parser tests |
| `mobile/test/backup_service_test.dart` | New — 11 backup tests |
| `backend/src/sarti_backend/core/config.py` | Added `email_worker_secret`, `gemini_api_key`, `fcm_credentials_file` |
| `backend/src/sarti_backend/db/schema.py` | Added `fcm_token`, `email_token_digest`, `email_suggestions` table |
| `backend/src/sarti_backend/api/email.py` | New — email ingest endpoint |
| `backend/src/sarti_backend/api/push.py` | New — push register and wake-up endpoints |
| `backend/src/sarti_backend/main.py` | Registered email/push routers; exposed `app.state.settings` |
| `backend/alembic/versions/0003_stage3_email_and_push.py` | New — migration 0003 |
| `backend/requirements.txt` | Added `firebase-admin==6.9.0` |
| `backend/openapi.json` | Regenerated |
| `backend/tests/unit/test_email_push.py` | New — 9 email/push unit tests |
| `docs/architecture/ADR-INDEX.md` | Added ADR-023 through ADR-026 |
| `docs/architecture/adr/023-natural-language-event-parsing.md` | New |
| `docs/architecture/adr/024-inbound-email-gateway.md` | New |
| `docs/architecture/adr/025-backup-and-recovery.md` | New |
| `docs/architecture/adr/026-push-notifications.md` | New |
| `docs/STATUS.md` | Updated to Stage 3 |
| `docs/modules/MODULES.md` | Added Stage 3 modules |
| `docs/api/API.md` | Documented email and push endpoints |
| `docs/database/DATABASE.md` | Added migration 0003 |

---

## ADRs

| ADR | Decision | Outcome |
| --- | --- | --- |
| ADR-023 | Deterministic parser always runs; Gemini cloud assist sends raw text only; `AiProvider` seam | Accepted before implementation |
| ADR-024 | Cloudflare Worker → FastAPI webhook; HMAC auth; injection sanitization; 7-day TTL; 20/day rate limit | Accepted before implementation |
| ADR-025 | PBKDF2-HMAC-SHA256 (200 k iterations) key derivation; XChaCha20-Poly1305 backup; 12-word BIP-39 phrase | Accepted; Argon2id excluded — `sodium_sumo` has no Flutter-compatible pinned package |
| ADR-026 | FCM opaque `{"type":"sync_available"}` payload only; OS-native lock screen sensitivity; no quiet-hours logic | Accepted before implementation |

Stop condition triggered during ADR-023: no stable Flutter package for Apple
NaturalLanguage or Gemini Nano exists. Gemini cloud approved with strict
raw-text-only rule. Implementation proceeded after explicit approval.

---

## APIs

| Endpoint | Method | Auth | Status |
| --- | --- | --- | --- |
| `/v1/email/ingest` | POST | `X-Worker-Secret` HMAC | New |
| `/v1/push/register` | POST | Bearer session | New |
| `/v1/push/wake-up` | POST | Bearer session | New |

OpenAPI regenerated and contract test passing.

---

## Migrations

| Revision | Change |
| --- | --- |
| `0003` | `fcm_token TEXT` nullable on `devices`; `email_token_digest BYTEA` nullable with partial unique index on `families`; `email_suggestions` table with status check constraint, content-digest unique constraint, and expiry/family composite indexes; schema version updated to 3 |

---

## Documentation updated

- `docs/STATUS.md` — stage, delivered list, verification table, gaps
- `docs/modules/MODULES.md` — `core/backup`, `features/ai`, `api.email`, `api.push`
- `docs/api/API.md` — email intake and push notification endpoint descriptions
- `docs/database/DATABASE.md` — migration 0003 history entry
- `docs/architecture/ADR-INDEX.md` — ADR-023 through ADR-026

---

## Tests added and executed

| Suite | Tests | Result |
| --- | --- | --- |
| `mobile/test/event_parser_test.dart` | 30 | Passed |
| `mobile/test/backup_service_test.dart` | 11 | Passed |
| `backend/tests/unit/test_email_push.py` | 9 | Passed |
| All backend unit tests | 17 | Passed |
| All mobile tests | 46 | Passed |

Total: 63 tests passing across backend and mobile.

---

## Tests not executed

- Physical iOS/Android passkey ceremony and biometric secure-storage policy
- Scheduled notification delivery on device
- Two-device network sync over a real transport
- FCM delivery with production credentials
- Cloudflare Worker → backend webhook end-to-end
- Gemini cloud assist against the live API
- Alembic upgrade/downgrade on a real PostgreSQL instance with migration 0003
  (Docker Compose integration test covers 0001/0002; 0003 covered by unit tests only)
- Backend integration test coverage with Stage 3 endpoints (PostgreSQL required)

---

## Security findings

- **Prompt injection** — `<INPUT>` delimiter stripping applied to subject and body
  before storage. Strict JSON schema output from Gemini limits injection surface.
  Raw email is never stored.
- **Family token exposure** — token is resolved via SHA-256 digest only; the raw
  token is never stored or logged.
- **FCM payload privacy** — only `{"type": "sync_available"}` is sent; no family
  IDs, child names, event titles, or any family content in the FCM payload
  (ADR-026 binding rule).
- **Worker secret** — HMAC constant-time comparison prevents timing attacks.
  Empty `email_worker_secret` causes all ingest requests to be rejected.
- **Backup phrase** — 12-word BIP-39 phrase provides ~128 bits of entropy.
  PBKDF2 with 200 k iterations provides key stretching. Wrong phrase or corrupted
  ciphertext both raise `BackupException`; no partial decryption is possible.
- No critical or high-severity vulnerabilities identified.

---

## Limitations

- `sodium_sumo` (required for Argon2id) has no Flutter-compatible pinned package.
  PBKDF2-HMAC-SHA256 is used instead per ADR-025. Argon2id remains the preferred
  KDF if a compatible package becomes available.
- Gemini Nano / Apple NaturalLanguage have no stable Flutter packages. Cloud
  Gemini is used with the raw-text-only privacy constraint.
- `firebase-admin` is a runtime dependency but is imported lazily inside
  `_send_fcm`; the backend starts without FCM credentials configured.
- The `email_suggestions` table has no consumer endpoint yet (mobile polling or
  server-sent events for suggestion delivery is a Stage 4 concern).

---

## Approval decisions

| Decision | Outcome |
| --- | --- |
| ADR-023: Gemini cloud assist with raw-text-only rule | Approved |
| ADR-024: Cloudflare Email Routing → FastAPI webhook | Approved |
| ADR-025: PBKDF2 instead of Argon2id | Approved |
| ADR-026: FCM opaque payload, OS-native sensitivity | Approved |

---

## Recommended next stage

**Stage 4 — suggestion delivery, export/deletion, and production readiness.**

Suggested scope (requires explicit approval before any implementation):

- Mobile endpoint to poll or receive `email_suggestions` and surface them as
  event proposals in the calendar UI
- User-controlled data export (ADR-017) and account/family deletion
- Production hosting decision; ADR-027 covers development/private beta only
- Associated domains / asset links for the production RP domain
- Privacy-preserving monitoring baseline (ADR-016)
- PostgreSQL-backed job runner for suggestion TTL expiry (ADR-013)

Do not begin Stage 4 without explicit approval.
