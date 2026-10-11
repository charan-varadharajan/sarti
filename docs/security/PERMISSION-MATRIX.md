# Permission matrix

| Action | Owner | Guardian | Pending/revoked/outsider |
| --- | --- | --- | --- |
| Create family | Yes | Yes, becomes owner of new family | Authenticated active device only |
| Create child resource | Yes | No | No |
| Create/approve invitation | Yes | No | No |
| Remove guardian / rotate epochs | Yes | No | No |
| Read encrypted resource operations | By membership plus `read`/`write`/`admin` | By assigned permission | No |
| Write encrypted resource operations | By `write`/`admin` | By assigned permission | No |
| Grant resource key | By `admin`, signed by active device | Only with explicit `admin` | No |
| Decrypt content | Authorized device holding current resource key | Same | No current key grant |

Children are profiles, not authenticated principals. Pickup/dropoff assignment
does not grant permissions. Server administrators can see bounded routing
metadata and ciphertext but do not receive family-content keys.
