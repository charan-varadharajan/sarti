# Database documentation

The mobile source of truth is SQLite backed by SQLCipher. PostgreSQL stores only
identity/authorization metadata, public keys, hashed tokens, signed sealed key
grants, and relay ciphertext. Field-level designs and classifications are in
`LOCAL-DATABASE.md` and `SERVER-DATABASE.md`.

## Migration history

| Revision | Store | Change | Verification |
| --- | --- | --- | --- |
| Local v1 | SQLCipher | Households, guardians, children, events, assignments, reminders | Fresh encrypted schema tests |
| Local v2 | SQLCipher | Outbox, de-duplication, conflicts, resource keys, cursor | Encrypted repository/sync tests |
| Local v3 | SQLCipher | Stable calendar resource, device sequence, conflict vectors | v2 encrypted-file upgrade preserves private content; wrong key fails |
| `0001` | PostgreSQL | Schema metadata/version 1 | Upgrade/downgrade/re-upgrade integration |
| `0002` | PostgreSQL | Identity, devices, families, permissions, invitations, grants, relay; version 2 | Real PostgreSQL migration and API integration |

Alembic upgrades run before backend startup. Local migrations use immediate
transactions and update `user_version` only after success.
