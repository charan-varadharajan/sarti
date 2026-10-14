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
  passkey and issue a new session. When replacing an active phone, the same
  transaction advances epochs of its accessible live resources, revokes the old
  phone/sessions and registers the replacement. Failed completion rolls back the
  transition; completed-challenge replay is rejected. Fresh device grants are
  required before future writes; login does not decrypt a backup.

Options/challenges expire in five minutes and are one-use. Completion includes
only WebAuthn output and 32-byte device public keys. Protected endpoints require
`Authorization: Bearer <opaque session token>`.

## Families and authorization

The complete mobile sharing/QR, review, permission and initial-state protocol is
in [Guardian onboarding](GUARDIAN-ONBOARDING.md) (ADR-035/BUG-004).

- `POST/GET /v1/families` creates/lists families and opaque resources. Creation
  optionally accepts a client-generated `family_id` and
  `calendar_resource_id` together so an offline-first family can be provisioned
  idempotently after connectivity returns.
- `POST /v1/families/{family_id}/resources` creates child-profile resources;
  owner only. Optional `resource_id` preserves the offline child UUID and makes
  retries idempotent; a family/kind/deletion collision returns 409. Optional
  `share_with_calendar_guardians` defaults to false. Explicit true grants read
  access to active calendar guardians at first provisioning only; retries never
  add later guardians. No profile content is accepted here.
- `POST /v1/families/{family_id}/invitations` creates a one-use 48-hour token.
- `POST /v1/invitations/accept` creates a pending membership.
- `POST .../invitations/{invitation_id}/approve` activates the guardian with an
  explicit resource permission list.
- `DELETE .../guardians/{guardian_id}` revokes access and advances key epochs.

Display names, child names, colours, and family details stay in encrypted mobile
content and are absent from these requests.

## Encrypted relay and grants

ADR-034 adds `protocol_version` to operation uploads/downloads. Allowed values
are 1 and 2; omission means 1 for legacy clients. New clients encrypt protocol 2
with fixed top-level fields and sorted version-map keys. The server stores the
version with ciphertext and compares it during exact retry validation; changing
only the version for an existing operation returns 409. Unknown versions return
422. The server cannot reinterpret or decrypt family content. Deploy migration/
backend first, then updated clients; legacy clients cannot decode protocol 2.
No automatic downgrade fallback is permitted.

- `POST /v1/sync/operations` accepts one bounded encrypted operation. An exact
  retry is idempotent; sequence gaps/replays and digest mismatches are 409. New
  stale-epoch writes are rejected. An exact already-accepted old-epoch retry may
  obtain its receipt under current write authorization; no new data is stored.
- `GET /v1/families/{family_id}/sync?cursor=N&limit=100` returns authorized,
  unexpired ciphertext and the next opaque cursor. Unauthorized resource rows
  are filtered while the cursor advances over scanned rows, so an unreadable
  child cannot block the readable calendar. A newly accepted key resets the
  local download cursor for bounded replay; operation IDs deduplicate it.
- `POST/GET /v1/key-grants` writes or retrieves signed sealed resource keys for
  the current active device. Wrapped 32-byte keys must be 80-byte sealed boxes.
  Exact retries return the same grant; a different grant for an existing
  recipient/epoch returns 409. The first granter establishes an epoch under a
  resource lock; another admin must receive that established key before extending
  it to another device. GET rechecks recipient permission, current epoch, and
  active/admin granter authorization.
- `GET /v1/families/{family_id}/resources/{resource_id}/devices` requires read
  access and returns only active authorized resource devices: opaque device ID,
  encryption/signing public keys, effective permission, and whether a current
  grant exists. It exposes no names, email addresses or private keys.

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

## Encrypted recovery (ADR-032)

`GET/PUT/DELETE /v1/families/{family_id}/backup` require an active authorized
owner device. PUT accepts a bounded v2 binary snapshot and an expected revision;
GET returns ciphertext and revision/time headers, never a recovery key. The
shipping app discovers a backup after login and restores only after explicit
phrase confirmation. See [backup protocol](BACKUP-RECOVERY.md).

## Adult and pet calendar extension — ADR-038

Resource creation additionally accepts `personal_calendar` (active adult's own
resource only; sharing flag rejected) and `participant_profile` (encrypted shared
profile labels). No profile name or appointment text appears in provisioning JSON.
Private-resource ownership overrides owner-wide household access on listings,
directories, key grants and sync. Explicit appointment sharing sends a different
event under the existing household calendar, without private identifiers/mappings.

`PUT/GET/DELETE /v1/families/{family_id}/personal-backup` use the authenticated
adult scope, not a caller-selected adult ID. Binary format, limits, revision
headers, no-store responses and structured errors match family backup endpoints.
See `BACKUP-RECOVERY.md`; generated `backend/openapi.json` is authoritative.
