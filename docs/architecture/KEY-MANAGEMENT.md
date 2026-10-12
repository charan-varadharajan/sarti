# Key management

ADR-020 defines the Stage 2 lifecycle.

| Material | Creation | Storage | Sharing | Rotation/destruction |
| --- | --- | --- | --- | --- |
| SQLCipher key | 32 random bytes from libsodium per installation | Keychain/Keystore via `flutter_secure_storage`, gated by `local_auth` | Included only inside user-phrase-encrypted v2 backup | Recovered into replacement protected storage; reset deletes local key |
| Device encryption key | X25519 key pair from libsodium | Public key on server; secret in platform secure storage | Public key registered during passkey ceremony | Replaced phone creates a new pair; old device is revoked |
| Device signing key | Ed25519 key pair from libsodium | Public key on server; secret in platform secure storage | Signs canonical resource-key grants | Same lifecycle as device encryption key |
| Resource key | 256 random bits per family/child/calendar resource and epoch | Inside SQLCipher on authorized devices | Libsodium sealed box per recipient device; grant is signed | Membership/device removal increments epoch and grants only to remaining devices |

Private content uses XChaCha20-Poly1305 with a new random 192-bit nonce. The
server persists sealed keys and opaque ciphertext only. A recipient must verify
the active granter and signature before accepting a grant. The backend rejects
grants for inactive devices, non-members, missing read permission, stale epochs,
or invalid signatures.

Revocation protects future writes. It cannot erase keys or plaintext already
copied to a removed device. ADR-031/032 define the implemented BIP-39 recovery phrase and v2 envelope.
The phrase derives an independent backup key; the server receives neither that
key nor the SQLCipher key. Recovery stages an integrity-checked database and
protected key journal, activates on startup after user presence, and retains the
new device identity. Old resource keys and sync bookkeeping are removed; fresh
grants are required for future synchronization. See `../api/BACKUP-RECOVERY.md`.
