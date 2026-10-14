# Encrypted backup and replacement-phone recovery

ADR-032 is the current design. Login authorizes download; the parent-held
12-word phrase decrypts locally. No file picker or provider credential is needed.

## API

- `PUT /v1/families/{family_id}/backup`: `application/octet-stream`, v2 `SART`
  blob, 94 bytes minimum and 10 MiB maximum. Required `X-Backup-Revision` header
  is the last observed revision (0 for first upload). Returns 204 and the new
  revision. A stale retry returns 409; it cannot overwrite a newer snapshot.
- `GET /v1/families/{family_id}/backup`: authenticated binary download; headers
  contain `X-Backup-Revision`, `X-Backup-Updated-At`, and `Cache-Control: no-store`.
  Missing/foreign/deleted family snapshots return 404.
- `DELETE /v1/families/{family_id}/backup`: explicit owner-authorized removal,
  retry-safe 204. Device authentication and active owner membership are required
  for all three operations. Restricted guardians cannot receive full snapshots.

`family_backups` has one primary-key row per family: revision, opaque ciphertext
and update time. Size/version are checked from the opaque file's public header.
Hard deletion cascades; setting `families.deleted_at` purges through a database
trigger. No TTL applies to this user-owned recovery snapshot. Previous snapshots
are replaced, not archived. Database-provider copies follow the provider's backup
retention, which still requires production policy validation.

## UI and local activation

From the authenticated calendar, select **Encrypted backup**, generate a phrase,
acknowledge it is saved, and select **Encrypt and upload backup**. Generating a
new phrase replaces the recovery secret for the new snapshot. Save the phrase
outside the phone. The phrase is cleared from UI after upload and is never
persisted by Sarti. The server cannot recover it.

An empty replacement installation automatically discovers owner snapshots after
login. **Restore encrypted backup** also retries discovery from onboarding.
Enter the phrase and select **Restore backup**. Existing local family data blocks
replacement to protect unsynced edits. The app validates the AEAD envelope,
SQLCipher database, schema, single-family scope, integrity and foreign keys.

The app writes only an encrypted staged file and a protected pending database key.
After the old database closes, startup activates the staged file/key. A pending
journal is retried after interrupted activation; success removes the journal.
Fresh device identity and session stay in secure storage. Old outbox, cursors,
resource keys and version tracking are removed; obtaining future resource grants
remains governed by normal authorization and BUG-004's pending guardian journey.
Old locally recovered content remains visible; this cannot restore future grants
or defeat revocation. Local preferences reset so cloud consent defaults off.

## Verification boundaries

Real PostgreSQL API/migration tests and real SQLCipher round-trip tests cover
software boundaries. Widget tests use prepared snapshots/screens and test explicit
actions. Physical two-phone passkeys, Keychain/Keystore, process interruption,
background/network behavior and production provider retention remain release
validation requirements. A malicious server can withhold or replay snapshots;
the UI exposes snapshot time and restoration remains explicit.

## Personal snapshots — ADR-038

Personal endpoints replace `/backup` with `/personal-backup` and authorize the
current active adult/membership, including guardians. Each adult has a separate
revisioned snapshot per family; another owner cannot retrieve or delete it.
Both APIs accept v2 ciphertext only; no permanent decryption key is held server-side.
The encrypted SQLCipher payload contains versioned `backup-scope-v1` identity,
validated against the authenticated adult before activation. An adult snapshot
excludes other adults' private content/keys/operations; family snapshots exclude
all private content and compact deleted encrypted pages before packaging.

Personal recovery preserves authorized historical resource keys, applied IDs and
event/profile vectors so old relay messages cannot overwrite newer restored edits.
It clears old sessions/device credentials/outbox envelopes/cursors/sequences;
current server epochs still gate future grants and writes. Household access starts
conservatively read-only pending authenticated refresh. These exceptions apply to
personal snapshots only; the preceding ADR-032 family restore behavior remains.
Recovery requires an empty local family and the correct phrase; wrong adult,
wrong phrase, malformed scope, integrity damage or corruption fails without
replacing the existing store. Choose My private backup from the calendar menu;
on a replacement installation choose the personal snapshot in recovery selection.

Each newly exported SQLCipher snapshot uses a fresh independent database key.
The v2 envelope wraps that snapshot key, never the live phone database key. A
family backup phrase therefore cannot unlock a separately acquired live phone
DB containing private appointments. Snapshot keys are erased from temporary
buffers after packaging; source DB encryption is unchanged.
