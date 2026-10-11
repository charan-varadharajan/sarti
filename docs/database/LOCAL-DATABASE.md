# Local SQLCipher database

Schema version 3 opens only after a 32-byte key is applied and
`PRAGMA cipher_version` succeeds. Foreign keys are enabled before migrations.
Migrations run under `BEGIN IMMEDIATE` and roll back on failure.

| Table | Purpose / notable constraints |
| --- | --- |
| `households` | Local family name and stable calendar resource UUID |
| `guardians` | Local encrypted display profiles, family FK |
| `children` | Encrypted name and ARGB calendar colour, family FK |
| `events` | Title/notes, IANA zone, local start, duration, status, recurrence, pickup/dropoff, revision, tombstone |
| `event_versions` | Last applied version vector per event for causal edits |
| `event_children` | Many-to-many event assignment, cascading FKs |
| `reminders` | Non-negative minutes before event |
| `outbox` | Atomic local operations with UUID, resource, plaintext inside SQLCipher, version vector, pending/uploaded state |
| `applied_operations` | Durable download de-duplication |
| `conflicts` | Both concurrent alternatives and vectors; open/resolved state |
| `resource_keys` | Resource UUID plus monotonic epoch and key, inside SQLCipher |
| `sync_state` | Per-family server cursor and next author-device sequence |

`ix_events_household_start` supports visible calendar range reads;
`ix_outbox_pending` supports ordered retry. Event children/reminders are replaced
atomically with an event. A remote event update restores these relationship rows.
The database file contains private content but is encrypted at rest; outbox JSON
becomes XChaCha20-Poly1305 ciphertext before leaving the device.
