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

ADR-040 family recovery preserves validated historical family resource keys in
the encrypted snapshot. Personal resources/keys remain excluded. Historical keys
only decrypt retained authenticated old-epoch messages; current owner/device,
resource permission, signed grants and exact directory epoch gate new writes.
Recovery key preparation excludes personal resources and automatic child/profile
publication. If an established epoch has other recipients but no verified grant
for this device, recovery waits rather than replacing it with a saved key.

## Guardian initial handoff (ADR-035)

After explicit pinned-device approval, current resource keys are wrapped only
for the active recipients allowed by each resource's permission. The family
profile's first owner key uses an unclaimed-epoch signed self-grant; an already
established key is never fabricated/replaced. Current events/tombstones retain
IDs/vectors and are encrypted under the calendar key; child names remain under
individual child keys; family/guardian names use the family-profile key. New
members read above the captured approval baseline. Key rotation on removal
still protects future updates and cannot erase historical copies.

## Personal calendar lifecycle (ADR-038)

- Creation: a random resource UUID is associated locally with one adult; its
  random 256-bit libsodium resource key is persisted in SQLCipher before publish.
- Storage: device secrets remain platform protected; resource keys remain in the
  SQLCipher store. Offline draft identity binds only once when authenticated.
- Sharing: the personal key is never shared with other household adults. Explicit
  appointment sharing uses a distinct event/household key, with no private mapping.
- Rotation/revocation: replacement advances only accessible household resources
  and the caller's personal resource. Other adults never get future personal keys.
- Recovery: own adult-scoped phrase-encrypted snapshot may restore historical
  resource keys and causal state; current-directory epochs authorize new grants.
  Old device identity/session/envelopes/sequences are never restored.
- Destruction: existing local reset destroys the SQLCipher key/store; personal
  snapshot deletion is adult-scoped. Family deletion purges server snapshots.
  Already copied plaintext, historical ciphertext/keys and provider backups cannot
  be remotely erased by unsharing. Production account deletion remains outstanding.

Adult replacement also advances that adult's live personal resources when a
household membership is inactive. Membership still gates server access; rotating
owned personal epochs prevents a previously revoked phone retaining a future key
if the adult later rejoins. It never rotates another adult's personal resource
through a household-owner bypass.


## ADR-041 foundation

Explicit scoped administrator grants replace implicit owner-wide public resource
rights after PostgreSQL 0012. Promotion alone grants no child/private key. New
membership narrowing/removal/expiry advances only lost public-resource epochs;
old snapshots/ciphertext are not re-encrypted or claimed erased. Sealed-key
publication continues through the established signed grant protocol and ordered
resource locks. Administration audit uses an independent permissioned resource;
no audit decryption key is held by the server. Caregiver broad calendar keys are
denied; actual reviewed independent scheduling-copy publication remains pending.

Local v10 binds personal resource IDs by adult and household. A device-global
upload counter serializes contexts without renumbering pending authenticated
bytes. Scoped snapshots remove foreign/excluded keys from an encrypted copy.
Current-phone step-up confirms intent without replacing device identity or keys.
