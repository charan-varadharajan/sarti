# PostgreSQL design

Stage 1 creates one table:

| Table | Field | Type | Constraint/classification |
| --- | --- | --- | --- |
| `schema_metadata` | `key` | text | Primary key; operational |
| `schema_metadata` | `value` | text | Not null; operational |
| `schema_metadata` | `updated_at` | timestamptz | Not null; operational |

The table records schema-level operational markers only. Migration `0001` creates
it and inserts `schema_version=1`; downgrade removes it. No family content,
identity, authorization, device, job, or relay schema exists yet.

Future tenant-bearing tables require explicit family scope, foreign keys,
constraints and indexes, data classification, retention, deletion behavior, and
two-family isolation tests. Relay payload schemas must store ciphertext only and
enforce a seven-day expiry timestamp.
