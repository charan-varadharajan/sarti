# ADR-019: Passkey sessions and device authorization

- Status: Accepted
- Date: 2026-10-11

Adults authenticate with discoverable WebAuthn passkeys using required user
verification. Sarti operates its own relying-party verifier with the maintained
Python `webauthn` library and Flutter `passkeys` adapter; no identity SaaS receives
account data. WebAuthn challenges are random, single use, expire after five
minutes, and are deleted after either successful use or expiry.

Successful authentication issues an opaque 256-bit session token. PostgreSQL
stores only its SHA-256 digest. Sessions expire after 30 days, are sent only in
the `Authorization` header over TLS, and are bound to one device record. Device
replacement atomically revokes the adult's existing active phone, its sessions,
and its ability to upload or download future key grants and relay operations.

Each adult has at most one active phone, enforced by a partial unique index.
Biometrics unlock device-held secrets and do not authenticate the device to the
server. Production relying-party ID, origin, Apple associated-domain file, and
Android asset links are deployment configuration because production hosting is
not selected. Local automated tests use verified WebAuthn fixtures; real native
ceremonies require the configured domain and physical-device testing.

Guardian invitations use 256-bit random bearer tokens. The server stores only a
SHA-256 digest, expiry, family, inviter, and status. Tokens expire after 48 hours,
are single use, and only create a pending membership. An existing family owner
must approve that membership and provision resource keys before it gains access.

