# Data flows

## Registration and device replacement

The API issues a five-minute WebAuthn challenge. The native authenticator returns
a credential assertion/attestation, and the device supplies only its X25519 and
Ed25519 public keys. The server verifies RP/origin and user verification, stores
public state, hashes the new session token, and revokes the prior active phone and
sessions in the same transaction.

## Local event and encrypted synchronization

The app commits event, assignments, reminders, and outbox operation in one
SQLCipher transaction. The sync engine encrypts the operation with the current
resource key and authenticated routing/version metadata. The API validates
authorization, order, epoch, digest, and replay constraints and retains opaque
ciphertext for seven days. A recipient verifies digest and authentication tag,
decrypts locally, and applies, ignores, or stores an explicit conflict according
to version vectors.

## Invitation and key delivery

The owner creates a hashed, expiring invitation. Acceptance creates only pending
membership. Owner approval activates explicit permissions. An authorized admin
device seals each resource key to the recipient X25519 public key and signs the
canonical grant with Ed25519. The server verifies permission, membership, epoch,
and signature but cannot unwrap the key.

## Local reminder

The device expands upcoming occurrences in the event IANA timezone and schedules
local notifications. Provider-visible text is generic; the payload holds an
opaque local event UUID. No server or push provider participates in Stage 2.

## Optional cloud-assisted event parsing

The deterministic parser always runs locally. If the parent has accepted the
current versioned disclosure, Sarti may construct the optional cloud adapter.
Before transmission it replaces known child names and locations under ADR-028.
The returned structured proposal is restored and validated locally. No proposal
mutates calendar state without explicit approval. With consent absent or revoked,
the provider is not constructed and local parsing continues.

## Native on-device event parsing

The deterministic parser runs first. When the platform reports its local model
ready, the Flutter method-channel bridge sends the sentence to Apple Foundation
Models or Android ML Kit Prompt API. No Sarti server participates. Native output
is parsed as untrusted JSON and can fill only unresolved deterministic fields.
Unavailable or invalid results fall back locally. The editable proposal requires
an explicit save action and offers Undo after persistence.

## Opaque push-assisted synchronization

After authentication, the device registers its current FCM token and token
rotations. A sending device uploads encrypted operations, then may request a
wake-up for the family. The backend authorizes the request and sends only
`{"type":"sync_available"}` to other active registered devices. A recipient
validates that exact shape, coalesces bursts, and requests the ordinary encrypted
sync path. Foreground transition also requests catch-up. The shipping bootstrap
restores an authenticated session, provisions an offline family with stable
client IDs, connects `SartiApiClient` to `SyncEngine`, and starts push
registration. Firebase configuration and physical-device delivery remain to be
tested.

## Inbound email suggestion

Cloudflare forwards bounded plaintext to the authenticated ingress. The backend
sanitizes the text, resolves the hashed family token, and holds plaintext only in
memory while sealing one JSON payload to each currently active device's X25519
public key. PostgreSQL stores digest/expiry metadata and per-device ciphertext.
The authenticated mobile app downloads only its delivery, decrypts locally,
shows the sender and untrusted-source warning, and requires the normal proposal
review and save action. Dismissal is device scoped.

Backup/restore remains blocked by the recovery design conflict recorded in
`docs/STATUS.md`.
