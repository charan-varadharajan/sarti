# Architecture decision record index

ADR-001 through ADR-018 record only decisions explicitly approved by the Sarti
Master Engineering Contract. Details the contract does not settle are listed as
unresolved rather than inferred.

| ADR | Decision | Status |
| --- | --- | --- |
| [ADR-001](adr/001-flutter-mobile.md) | Flutter and Dart mobile clients | Accepted |
| [ADR-002](adr/002-fastapi-modular-monolith.md) | FastAPI modular-monolith backend | Accepted |
| [ADR-003](adr/003-encrypted-local-storage.md) | SQLite and SQLCipher local storage | Accepted |
| [ADR-004](adr/004-postgresql-metadata.md) | PostgreSQL operational metadata | Accepted |
| [ADR-005](adr/005-device-identity.md) | Passkeys, biometrics, and active-phone policy | Accepted |
| [ADR-006](adr/006-resource-scoped-e2ee.md) | Resource-scoped E2EE | Accepted; protocol unresolved |
| [ADR-007](adr/007-offline-sync.md) | Offline-first encrypted synchronization | Accepted; protocol unresolved |
| [ADR-008](adr/008-relay-retention.md) | Seven-day ciphertext relay retention | Accepted |
| [ADR-009](adr/009-on-device-ai.md) | On-device AI and deterministic fallback | Accepted |
| [ADR-010](adr/010-email-boundary.md) | Inbound email plaintext boundary | Accepted; provider unresolved |
| [ADR-011](adr/011-private-push.md) | Privacy-preserving push notifications | Accepted |
| [ADR-012](adr/012-authorization.md) | Role and resource authorization | Accepted |
| [ADR-013](adr/013-postgres-jobs.md) | PostgreSQL-backed jobs | Accepted |
| [ADR-014](adr/014-riverpod.md) | Riverpod state management | Accepted |
| [ADR-015](adr/015-backup-recovery.md) | User-owned encrypted backup and recovery | Accepted; format unresolved |
| [ADR-016](adr/016-private-monitoring.md) | Privacy-preserving monitoring | Accepted |
| [ADR-017](adr/017-export-deletion.md) | User-controlled export and deletion | Accepted |
| [ADR-018](adr/018-local-development-hosting.md) | Docker local development; hosting undecided | Accepted |
| [ADR-019](adr/019-passkey-sessions-and-device-authorization.md) | Passkey sessions and active-device authorization | Accepted |
| [ADR-020](adr/020-device-and-resource-key-protocol.md) | Device keys and resource-scoped encryption protocol | Accepted |
| [ADR-021](adr/021-encrypted-operation-sync-and-conflicts.md) | Encrypted operation sync and explicit conflicts | Accepted |
| [ADR-022](adr/022-calendar-time-permissions-and-reminders.md) | Calendar time semantics, permissions, and reminders | Accepted |
| [ADR-023](adr/023-natural-language-event-parsing.md) | Natural-language event parsing and AI assist | Accepted |
| [ADR-024](adr/024-inbound-email-gateway.md) | Inbound email gateway | Accepted |
| [ADR-025](adr/025-backup-and-recovery.md) | User-owned encrypted backup and recovery | Accepted |
| [ADR-026](adr/026-push-notifications.md) | Push notifications | Accepted |
| [ADR-027](adr/027-beta-hosting-cloud-run-neon.md) | Cloud Run and Neon Free for beta hosting | Accepted |

New records use the next three-digit number. Accepted decisions are changed only
by an explicitly approved superseding ADR.
