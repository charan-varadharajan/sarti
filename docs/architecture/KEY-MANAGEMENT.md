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

BUG-003 wires the mobile grant protocol into authenticated synchronization.
Before provisioning a new child, the owner persists a random independent key
inside SQLCipher. The owner self-grants first, then wraps the same key separately
for each active authorized recipient and signs the existing `SARTI-GRANT-V1`
canonical fields. The authenticated session device ID is used, rather than the
installation-local UUID. Recipients verify resource/epoch/recipient scope,
active administrator identity, signature and sealed-box decryption. A different
key for an already-held epoch is rejected without replacing it.

For an advanced epoch, an active admin holding the previous key may propose a
fresh random key through a signed self-grant. The server resource lock and first
granter check serialize contenders; a loser waits for the established grant.
The key is committed locally only after acceptance; a lost response is recovered
by opening the self-grant on the next pass. Current-epoch keys are then granted
only to active resource-authorized devices. No missing existing key is fabricated
at the same epoch. Old keys remain available for retained historical ciphertext;
revocation cannot retract earlier copies. Local destruction follows the existing
database/device-reset lifecycle; the server never receives plaintext keys.

## Device replacement (BUG-010)

Passkey completion serializes on the adult row, then locks accessible live
resources in UUID order. Active owners rotate all live family resources;
active guardians rotate only explicitly permitted resources. Pending/revoked
memberships and deleted families/resources are excluded. Epoch advancement,
old-phone/session revocation, new device registration and new session creation
commit together. A failed transaction rolls all of these back; replaying a
completed challenge cannot advance epochs again. Distinct concurrent successful
replacements serialize and each replaces the preceding phone.

Uploads and grants lock the resource before inspecting its epoch; grants recheck
active granter state after the lock. A stale new upload fails; an exact existing
receipt does not publish new ciphertext. Remaining admins generate random keys,
self-grant under the existing first-granter lock and distribute only to active
authorized devices. An interrupted self-grant is recovered from the sealed grant
before retry, so an accepted key is never silently replaced.

ADR-032 clears historical resource keys during restore. An authorized admin with
no historical key may initialize an advanced epoch (>1) only when the directory
shows no current grant. The server first-granter rule remains authoritative in a
race. An initial missing key or already established epoch is never fabricated.
Without a current key, writes remain pending. Historical content still needs
its appropriate snapshot/key; fresh grants do not recreate expired relay data.
No server plaintext key custody or backup decryption is introduced.

## Guardian initial handoff (ADR-035)

After explicit pinned-device approval, current resource keys are wrapped only
for the active recipients allowed by each resource's permission. The family
profile's first owner key uses an unclaimed-epoch signed self-grant; an already
established key is never fabricated/replaced. Current events/tombstones retain
IDs/vectors and are encrypted under the calendar key; child names remain under
individual child keys; family/guardian names use the family-profile key. New
members read above the captured approval baseline. Key rotation on removal
still protects future updates and cannot erase historical copies.
