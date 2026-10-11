# Database documentation

No schemas or migrations exist in Stage 1.

## Planned stores

- Device: SQLite encrypted with SQLCipher, containing private family state,
  pending sync operations, and migration metadata.
- Server: PostgreSQL containing minimized operational metadata, authorization and
  active-device state, job state, and relay ciphertext with seven-day retention.

Each implemented table must document every field, relationship, index, unique and
check constraint, retention rule, data classification, and encryption boundary.
This directory will also contain ER diagrams and chronological migration history.

Schema names and fields are deliberately unspecified until resource, sync, key,
and authorization models are approved.
