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
| Local v4 | SQLCipher | Private child cloud aliases and unique family alias index | Encrypted legacy-profile backfill |
| Local v5 | SQLCipher | Versioned app preferences | Consent defaults and persistence |
| Local v6 | SQLCipher | Durable retry envelopes, hidden child placeholders, resource catalog, child sync/consent markers; BUG-003 | v5 encrypted-file upgrade preserves profiles, assignments and pending writes; wrong-key rejection |
| `0001` | PostgreSQL | Schema metadata/version 1 | Upgrade/downgrade/re-upgrade integration |
| `0002` | PostgreSQL | Identity, devices, families, permissions, invitations, grants, relay; version 2 | Real PostgreSQL migration and API integration |
| `0003` | PostgreSQL | `fcm_token` nullable column on `devices`; `email_token_digest` nullable column with partial unique index on `families`; `email_suggestions` table with status check constraint and expiry/family indexes; version 3 | Unit tests; Alembic upgrade to head |
| `0004` | PostgreSQL | Removes plaintext sender/subject/body/status from `email_suggestions`; adds device-scoped sealed-ciphertext deliveries; version 4 | Real PostgreSQL upgrade and API integration; encrypted delivery unit tests |
| `0005` | PostgreSQL | One opaque, bounded, revisioned backup per family; cascade and soft-delete purge; version 5 | Upgrade/downgrade/re-upgrade and owner/tenant/device API tests |

| Local v7 | SQLCipher | Personal resource bindings, typed adult/pet profiles/assignments, private/shared mapping, durable child vectors; ADR-038 | Encrypted upgrade and regression; prior rows/colours/envelopes retained |
| `0006` | PostgreSQL | Versioned sync metadata for deterministic AAD | Real JSONB/crypto round trip; legacy preservation |
| `0007` | PostgreSQL | Guardian approval relay baseline | Approval/retained-state tests; guarded downgrade |
| `0008` | PostgreSQL | Private adult resource ownership, unique live binding, participant kind, scoped personal backups and purge | PostgreSQL upgrade/downgrade and owner/guardian/outsider/device security tests |

Alembic upgrades run before backend startup. Local migrations use immediate
transactions and update `user_version` only after success.

| Local v8 | SQLCipher | Minimal calendar deletions, retention conflicts; secure-delete; migration never sweeps history | RETENTION-MIG-001 |
| `0009` | PostgreSQL | Family retention enum/enabled/revision; legacy default disabled; guarded downgrade | RETENTION-MIG-002 |

| Local v9 | SQLCipher | Recovery gate and quarantined intent/exact reviewed-operation mapping; preserved history; legacy marker blocks | RECOVERY-MIG and RECOVERY-CONT tests |
