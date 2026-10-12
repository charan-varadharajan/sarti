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

Inbound email, backup/restore, and remote push are Stage 3 flows whose backend
components exist but whose complete mobile acceptance flows remain unintegrated.
