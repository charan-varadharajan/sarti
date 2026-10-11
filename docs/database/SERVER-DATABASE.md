# PostgreSQL database

Migration `0001` creates `schema_metadata`. Migration `0002` creates:

| Area | Tables | Stored data |
| --- | --- | --- |
| Identity | `adults`, `webauthn_credentials`, `webauthn_challenges`, `sessions`, `devices` | Public credentials/keys, hashed tokens, expiry/state, counters |
| Tenant auth | `families`, `memberships`, `resources`, `resource_permissions`, `guardian_invitations` | Opaque UUIDs, roles, permission levels, hashed invite token, key epoch |
| Encryption relay | `resource_key_grants`, `sync_operations` | Signed sealed keys, authenticated routing metadata, opaque ciphertext, seven-day expiry |

Foreign keys, enum-like checks, unique invitation/operation constraints, positive
sequence/epoch constraints, and a partial unique index enforce one active device
per adult. Relay operations are indexed by family/server sequence and expiry.
The schema contains no family names, event titles, notes, child names, colours,
pickup details, reminders, or resource keys in decryptable form.

The migration suite upgrades a real PostgreSQL database, asserts schema version 2
and required tables, and exercises the constraints through the full API flow.
