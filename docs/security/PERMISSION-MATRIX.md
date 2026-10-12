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
