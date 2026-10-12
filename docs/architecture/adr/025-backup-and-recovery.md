# ADR-025: User-owned encrypted backup and recovery

- Status: Accepted
- Date: 2026-10-12

## Implementation conformance audit

ADR-031 supersedes this record's recovery-phrase rules and brings phrase
generation and validation into BIP-39 conformance. The raw SQLCipher payload
still does not define how a replacement device recovers the independent
SQLCipher database key. Backup recovery is therefore not an accepted feature
until BUG-002 is resolved through a separately approved ADR.

## Decision

Backups are encrypted on-device before leaving the app. The backup key is
derived from a user-held recovery phrase. Sarti servers never receive or store
the backup key or any plaintext backup content.

## Recovery phrase

A 12-word BIP-39 mnemonic is generated using libsodium's secure random source
at first family creation. The user is shown the phrase once and must acknowledge
saving it. The phrase is not stored by Sarti anywhere after display.

## Key derivation

Backup key = PBKDF2-HMAC-SHA256(phrase_bytes, salt, iterations=200000, keylen=32).
The salt is random 16 bytes generated per backup and stored in the backup file
header in plaintext. PBKDF2 is implemented using the `crypto` package already
in the project — no new dependency. Argon2id would be preferable but requires
`sodium_sumo` which is not available as a Flutter-compatible pinned package;
this is documented as a known limitation for Stage 3.

## Backup format

```
[4 bytes]  magic: 0x53415254 ("SART")
[1 byte]   version: 0x01
[16 bytes] salt (Argon2id input)
[24 bytes] nonce (XChaCha20-Poly1305)
[N bytes]  ciphertext (encrypted SQLCipher database export)
[16 bytes] Poly1305 authentication tag (appended by libsodium)
```

The encrypted payload is the raw SQLCipher database file bytes. The backup key
is independent from all sync resource keys and the SQLCipher database key.

## Integrity check

Decryption fails with an authentication tag error if the file is corrupted or
the wrong recovery phrase is used. No partial decryption is possible.

## Restore workflow

1. User installs Sarti on a new device.
2. User selects "Restore from backup" and picks the backup file.
3. User enters their 12-word recovery phrase.
4. App derives the backup key, decrypts the file, validates the tag.
5. On success: the decrypted database is written to the app's private directory
   and opened with the existing SQLCipher key derivation flow.
6. On failure: error shown, no partial data written.

## Export destinations

The app presents the backup file via the platform share sheet. The user chooses
the destination (iCloud Drive, Google Drive, local files, AirDrop, etc.).
Sarti does not integrate with any specific cloud storage provider.

## What is not backed up

- Device private keys (X25519, Ed25519) — these are device-specific and
  non-exportable. After restore, the user must re-authenticate to get new
  resource key grants from another authorized device.
- Session tokens — expire and are re-issued on authentication.

## Independence from sync encryption

Backup key derivation uses PBKDF2-HMAC-SHA256 from a user phrase. Sync resource keys are
random 256-bit keys wrapped in libsodium sealed boxes. The two systems share no
key material and cannot be used to attack each other.

## New dependency

None. PBKDF2-HMAC-SHA256 uses the `crypto` package already in the project.
XChaCha20-Poly1305 uses the `sodium` package already in the project.
