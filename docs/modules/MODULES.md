# Module catalog

This is the intended responsibility map, not an implemented module inventory.

## Mobile

- App shell and onboarding
- Identity, passkeys, and local access
- Family profiles and authorization view
- Calendar, recurrence, colours, and pickup assignments
- Suggestions and explicit approval
- Native AI and deterministic parsing adapters
- Encrypted local persistence
- Encryption and key lifecycle
- Offline sync and conflict resolution
- Local notifications
- Encrypted backup and restore

## Backend

- Identity and active-device registry
- Families, roles, and resource authorization metadata
- Ciphertext relay and retention
- PostgreSQL-backed jobs
- Email intake orchestration
- Privacy-preserving push dispatch
- Backup coordination metadata
- Export, deletion, and operational administration

Before a module is implemented, add its responsibilities, public interfaces,
dependencies, state ownership, error behavior, security assumptions, and test
coverage here or in a linked module document.
