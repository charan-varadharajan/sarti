# ADR-020: Device and resource key protocol

- Status: Accepted
- Date: 2026-10-11

The mobile app uses libsodium through the maintained Dart `sodium` package. Each
installation generates an X25519 encryption key pair and Ed25519 signing key pair.
Private keys and a random 256-bit SQLCipher database key are kept in iOS Keychain
or Android Keystore through `flutter_secure_storage`, with biometric access gated
through `local_auth`. Device secrets are non-exportable at the application layer,
never sent to Sarti, and destroyed locally at sign-out or device reset.

Every family profile, child profile, and family calendar is a resource with a
random 256-bit key and monotonically increasing key epoch. Private resource
content uses XChaCha20-Poly1305 with a fresh random 192-bit nonce. Protocol
version, family ID, resource ID, key epoch, operation ID, author device ID, device
sequence, and logical version are authenticated as additional data. Ciphertext is
never processed before authentication succeeds.

Resource keys are wrapped separately to each active authorized device using
libsodium sealed boxes and recorded as ciphertext-only key grants. The granting
device signs the canonical grant fields and wrapped-key digest with Ed25519. The
recipient verifies the active granter and signature before accepting a key.

Removing a guardian or replacing a device creates a new resource-key epoch and
new grants only for remaining authorized devices. New writes use the new epoch;
old ciphertext is not re-encrypted automatically. Revocation therefore protects
future content but cannot erase keys or plaintext already copied by a device.
Destroying a family removes server metadata, relay ciphertext, and grants; active
devices delete local databases, SQLCipher keys, device private keys, and cached
resource keys. Recovery and user-owned backup remain governed by ADR-015 and are
not weakened by this protocol.

