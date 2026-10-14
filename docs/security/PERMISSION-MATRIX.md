# Permission matrix

| Action | Owner | Guardian | Pending/revoked/outsider |
| --- | --- | --- | --- |
| Create family | Yes | Yes, becomes owner of new family | Authenticated active device only |
| Create child resource | Yes | No | No |
| Share new child profile with existing calendar guardians | Explicit owner opt-in at first provisioning; read only | No implicit access | No |
| Create/approve invitation | Yes | No | No |
| Remove guardian / rotate epochs | Yes | No | No |
| Read encrypted resource operations | By membership plus `read`/`write`/`admin` | By assigned permission | No |
| Write encrypted resource operations | By `write`/`admin` | By assigned permission | No |
| Grant resource key | By `admin`, signed by active device | Only with explicit `admin` | No |
| Decrypt content | Authorized device holding current resource key | Same | No current key grant |

Children are profiles, not authenticated principals. Pickup/dropoff assignment
does not grant permissions. Server administrators can see bounded routing
metadata and ciphertext but do not receive family-content keys.

BUG-003 leaves new child permissions empty for guardians unless the owner
explicitly selects sharing. Consent snapshots active calendar guardians at first
server provisioning; retries do not extend it. Resource-device discovery requires
read access and excludes pending/revoked members and inactive devices. Key
publication still requires admin; read-only sharing never grants child creation,
key administration, or access to another resource.

## Mobile guardian enrollment (ADR-035 / BUG-004)

| Action | Owner | Approved guardian | Pending/revoked |
| --- | --- | --- | --- |
| Share/copy/display invitation QR; review/cancel requests | Owner's authenticated active phone | No | No |
| Accept a valid one-use invitation | Cannot accept own token | Only before attaching a local family | Authenticated candidate may enter pending |
| Approve device/permissions and initial state | Compare code, pin device/digest, choose resource subset | No | No |
| View calendar offline/online | Yes | Read/write/admin for that calendar; server checks online | No new content; revoked earlier copies cannot be erased |
| Create/edit/delete/resolve events | Yes | Write/admin only; read-only UI disables mutation controls | No |
| Add children or administer sharing | Yes | No through this UI | No |
| Receive private child names/colours | Yes | Only separately selected child read grants | No new grants |
| Receive family/guardian profile names | Yes | Explicit family-profile read grant | No |
| Download owner's whole encrypted backup | Owner only | No | No |

Approval payloads are a nonempty subset without duplicates. New clients pin the
reviewed device and full public-key digest. Pending family lists contain no
resources; active guardian lists contain only permitted ones. The server relay
baseline cannot be bypassed by resetting a client cursor. UI permissions are
cached only in SQLCipher; the API remains independently authoritative. Names,
colours, key plaintext and recovery phrases are absent from invitation transport.

## ADR-038 exceptions and additions

The preceding owner-wide resource rules apply to household resources only.

| Action | Private author | Other household owner/guardian | Outsider/revoked device |
| --- | --- | --- | --- |
| List/read/write/admin personal resource | Own active adult/device only | Denied, even owner | Denied |
| Receive/grant personal key | Own active adult/device only | Denied | Denied |
| Retrieve/replace/delete personal backup | Own adult scope; active membership | Own snapshot only, never author's | Denied |
| Read explicit household copy | Calendar permission required | Calendar permission required | Denied future access |
| Provision shared adult/pet profile resource | Active member; shared metadata only | Owners can administer household profiles | Denied |

Personal-resource creation rejects a sharing flag and cannot reuse another
adult's resource ID. Invitations exclude personal resources at UI and API layers.
Replacement advances the author's accessible personal epoch, never another
adult's personal epoch merely because the caller owns the family. Guardian
removal rotates household resources without granting any personal resource key.
Pickup/profile references confer no additional access. UI adult/pet names are
editable labels, not verified authentication identities.

## ADR-039 calendar retention

Family policy read requires active membership/device. Change requires owner or
explicit `admin` on a live household calendar; `write` is insufficient. An admin
setting applies one family period but grants no access to private resources/keys.
Shared cleanup originates from an authorized admin; each private author handles
its own resource. Unknown/stale authority and incomplete catch-up defer cleanup.
Existing write permissions continue governing encrypted event deletion/resolution.

## Recovery (ADR-040)

Historical snapshot keys/cached ACLs never authorize current writes. Fresh active
owner membership, current resource admin permission and verified exact current
epoch are required to approve/publish recovered intent or resume cleanup. Recovery
excludes personal resources even from key preparation. New child/profile resources
require explicit recipient review; deleted/missing calendars are not resurrected.
Server independently rejects revoked devices, stale epochs, foreign resources and
replays. Incomplete history stays read-only; no old credentials are restored.

Family/guardian/child name edits require the existing owner cache for offline UI
and current resource permission for server uploads. Display-name editing never
changes membership, role, resource grants or revocation. The hub routes removal
through existing current-server authorization. Optional cloud API requires an
active authenticated device and disclosure v3 request, no family-content access
API. Token/response validation and quota are independent of encrypted sync.
