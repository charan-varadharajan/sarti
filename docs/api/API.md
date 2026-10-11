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

- `POST/GET /v1/families` creates/lists families and opaque resources.
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
