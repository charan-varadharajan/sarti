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
