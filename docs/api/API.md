# API documentation

The reviewed OpenAPI 3.1 contract is committed at `backend/openapi.json` and
checked for drift. Runtime documentation routes remain disabled. All errors use
the sanitized envelope in `CONVENTIONS.md`; private content is never accepted as
plaintext.

## Health

- `GET /v1/health/live` reports process liveness.
- `GET /v1/health/ready` executes a PostgreSQL readiness check.

## Passkeys and devices

- `POST /v1/auth/registration/options` and `/registration/complete` create the
  adult, credential, active device, and session.
- `POST /v1/auth/authentication/options` and `/authentication/complete` verify a
  passkey, rotate the active phone when necessary, and issue a new session.

Options/challenges expire in five minutes and are one-use. Completion includes
only WebAuthn output and 32-byte device public keys. Protected endpoints require
`Authorization: Bearer <opaque session token>`.

## Families and authorization

- `POST/GET /v1/families` creates/lists families and opaque resources. Creation
  optionally accepts a client-generated `family_id` and
  `calendar_resource_id` together so an offline-first family can be provisioned
  idempotently after connectivity returns.
- `POST /v1/families/{family_id}/resources` creates child-profile resources;
  owner only.
- `POST /v1/families/{family_id}/invitations` creates a one-use 48-hour token.
- `POST /v1/invitations/accept` creates a pending membership.
- `POST .../invitations/{invitation_id}/approve` activates the guardian with an
  explicit resource permission list.
- `DELETE .../guardians/{guardian_id}` revokes access and advances key epochs.

Display names, child names, colours, and family details stay in encrypted mobile
content and are absent from these requests.

## Encrypted relay and grants

- `POST /v1/sync/operations` accepts one bounded encrypted operation. An exact
  retry is idempotent; sequence gaps/replays and digest/epoch mismatches are 409.
- `GET /v1/families/{family_id}/sync?cursor=N&limit=100` returns authorized,
  unexpired ciphertext and the next opaque cursor.
- `POST/GET /v1/key-grants` writes or retrieves signed sealed resource keys for
  the current active device.

The complete field constraints and response schemas are in `backend/openapi.json`.
The encryption/AAD construction is specified in `docs/architecture/OFFLINE-SYNC.md`.

## Email intake (ADR-024)

- `POST /v1/email/ingest` — Cloudflare Worker webhook only. Authenticated via
  `X-Worker-Secret` header (HMAC constant-time comparison). Accepts
  `family_token`, `sender`, `subject`, and `body`. The family token is resolved
  to a family ID via its SHA-256 digest; an unknown token returns 404.
  `<INPUT>` tags are stripped from subject and body before encryption. Rate limited
  to 20 emails per family per 24 hours. Identical content (same digest) is
  deduplicated and returns the existing suggestion ID. Suggestions expire after
  7 days. The backend seals the sanitized sender, subject, and body separately
  to every active device and persists ciphertext only. Returns `suggestion_id`
  and `expires_at` on 201.
- `GET /v1/email/suggestions` — Authenticated. Returns only pending encrypted
  deliveries addressed to the calling active device. Ciphertext is base64url.
- `DELETE /v1/email/suggestions/{suggestion_id}` — Authenticated. Dismisses only
  the calling device's delivery and returns 204.

## Push notifications (ADR-026)

- `POST /v1/push/register` — Authenticated. Stores the FCM token for the
  calling device. Returns `{"registered": true}`.
- `POST /v1/push/wake-up` — Authenticated. Accepts `family_id`. Verifies the
  caller is an active member, then sends `{"type": "sync_available"}` to all
  other active family devices that have a registered FCM token. No family
  content, child names, or event data is included in the FCM payload. Returns
  `{"dispatched": N}`. If `fcm_credentials_file` is not configured, returns
  `{"dispatched": 0}` without error.
