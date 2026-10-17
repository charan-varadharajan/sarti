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
| [ADR-015](adr/015-backup-recovery.md) | User-owned encrypted backup and recovery | Accepted; specified by ADR-025/031/032 |
| [ADR-016](adr/016-private-monitoring.md) | Privacy-preserving monitoring | Accepted |
| [ADR-017](adr/017-export-deletion.md) | User-controlled export and deletion | Accepted |
| [ADR-018](adr/018-local-development-hosting.md) | Docker local development; hosting undecided | Accepted |
| [ADR-019](adr/019-passkey-sessions-and-device-authorization.md) | Passkey sessions and active-device authorization | Accepted |
| [ADR-020](adr/020-device-and-resource-key-protocol.md) | Device keys and resource-scoped encryption protocol | Accepted |
| [ADR-021](adr/021-encrypted-operation-sync-and-conflicts.md) | Encrypted operation sync and explicit conflicts | Accepted |
| [ADR-022](adr/022-calendar-time-permissions-and-reminders.md) | Calendar time semantics, permissions, and reminders | Accepted |
| [ADR-023](adr/023-natural-language-event-parsing.md) | Natural-language event parsing and AI assist | Accepted |
| [ADR-024](adr/024-inbound-email-gateway.md) | Inbound email gateway | Accepted |
| [ADR-025](adr/025-backup-and-recovery.md) | User-owned encrypted backup and recovery | Accepted; phrase/payload/restore superseded by ADR-031/032 |
| [ADR-026](adr/026-push-notifications.md) | Push notifications | Accepted |
| [ADR-027](adr/027-beta-hosting-cloud-run-neon.md) | Cloud Run and Neon Free for beta hosting | Accepted |
| [ADR-028](adr/028-cloud-prompt-pseudonymization.md) | Local pseudonymization before optional cloud AI | Accepted; transmission policy superseded by ADR-036 |
| [ADR-029](adr/029-native-on-device-ai-bridges.md) | Apple Foundation Models and Android ML Kit on-device AI bridges | Accepted |
| [ADR-030](adr/030-release-versioning.md) | Repository-wide SemVer and mobile build numbering | Accepted |
| [ADR-031](adr/031-bip39-recovery-phrase-conformance.md) | BIP-39 recovery-phrase conformance | Accepted; supersedes ADR-025 phrase rules |
| [ADR-032](adr/032-portable-encrypted-backup-relay.md) | Portable encrypted snapshot and owner-authorized recovery relay | Accepted; supersedes ADR-025; personal extension in ADR-038; family continuation in ADR-040 |
| [ADR-033](adr/033-kalender-calendar-presentation.md) | Kalender presentation adapter for day/week/month grids | Accepted |
| [ADR-034](adr/034-versioned-sync-metadata-encoding.md) | Versioned deterministic sync metadata with legacy preservation | Accepted; supersedes ADR-020/021 serialization detail |

| [ADR-035](adr/035-guardian-invitations-and-scoped-handoff.md) | Shared/copied/QR guardian invitations and scoped encrypted initial handoff | Accepted within approved BUG-004 scope |

| [ADR-036](adr/036-request-scoped-cloud-privacy.md) | Request-scoped labels, minimized cloud input and accurate privacy claims | Accepted; supersedes ADR-028 cloud transmission policy |

| [ADR-037](adr/037-server-managed-cloud-assist.md) | Server-managed cloud assist, paid-service gate and bounded usage | Accepted 2026-10-14; disabled implementation only; live activation separate |

New records use the next three-digit number. Accepted decisions are changed only
by an explicitly approved superseding ADR.

| [ADR-038](adr/038-adult-private-appointments-and-pet-profiles.md) | Adult private appointments, explicit household copies and pet profiles | Accepted; implementation and verification in ADR-038 report |

| [ADR-039](adr/039-rolling-calendar-history-retention.md) | Family-admin-managed mobile calendar retention | Accepted by maintainer 2026-10-13; implementation verification recorded separately |

| [ADR-040](adr/040-family-recovery-continuation.md) | Safe family recovery continuation, recovered intent review and retention resume (BUG-022) | Accepted 2026-10-13; supersedes family-history clearing and unconditional retention pause |

| [ADR-041](adr/041-stage5-scoped-membership-and-sensitive-operations.md) | Stage 5 scoped roles, multi-admin/household, caregiver encryption, step-up, assisted recovery, audit and deletion/restore | Accepted by maintainer 2026-10-16; implementation in progress |
