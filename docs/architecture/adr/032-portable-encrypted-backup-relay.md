# ADR-032: Portable encrypted backup and family relay

- Status: Accepted
- Extension (2026-10-13): ADR-038 adds a separate adult-scoped snapshot/recovery path and excludes private state from family snapshots; see its explicit personal recovery exception.
- Date: 2026-10-12
- Supersedes: ADR-025 payload, restore, and export destination rules
- Approval: User approved the v2 key envelope and subsequently approved the
  automatic Sarti-hosted ciphertext relay and its UI/API/test implementation.

## Decision

Format v2 encrypts the 32-byte SQLCipher key followed by the SQLCipher file using
the existing recovery-phrase-derived key and authenticated encryption. No device
identity private keys or sessions are included. The phrase remains user-held;
login authorizes download but cannot decrypt a backup.

An explicit backup action uploads an opaque v2 blob. PostgreSQL keeps one latest
blob per family, capped at 10 MiB, until replaced, explicitly deleted, or its
family is deleted. This durable snapshot is separate from the seven-day sync
relay. Upload uses compare-and-swap revision checking to prevent stale retries
overwriting a newer snapshot. The server stores family ID, revision, ciphertext,
and update time only (format and size are derived from the blob); logs never contain the blob or keys.

A full-family snapshot includes all resource content and keys, so every operation
requires an active device and owner membership. Restricted guardians must use
resource-scoped synchronization rather than download a full database snapshot.
This restriction prevents backup recovery bypassing child-resource permissions.

After login on an empty replacement installation, the app discovers authorized
family backups automatically. The parent enters the phrase and confirms restore.
The app validates authentication, SQLCipher integrity, schema and family scope
before activation. A staged encrypted file and protected pending key allow
interruption-safe activation on startup. Existing family content is not silently
overwritten. Restored sync state and keys are cleared before future sync; new
device identity and fresh grants remain required.

Backup creation uses a consistent database snapshot and is limited to a single
family database. Restore preserves that family's local data but never restores
session credentials or the old device identity. No new dependency is introduced.

## Tests and limitations

Test tenant/owner isolation, replaced devices, bounded/malformed uploads,
revision conflicts, deletion, v2 decryption, wrong phrases, damaged snapshots,
family/schema mismatch, staged recovery, protected-storage failure, and UI
confirmation. Mock tests do not establish physical Keychain/Keystore or live
two-device compatibility. Server operators can delete or replay stored snapshots;
the UI exposes server revision/time and recovery is an explicit snapshot action.
