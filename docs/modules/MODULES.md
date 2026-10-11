# Module catalog

## Mobile

| Module | Responsibility | Principal tests |
| --- | --- | --- |
| `core/auth` | Native passkey adapter | Backend contract; physical platform pending |
| `core/crypto` | Device keys, secure storage, XChaCha20-Poly1305 resource content | Encrypted sync simulation |
| `core/database` | SQLCipher verification, schema v1-v3, transactional migrations | Native engine and repository tests |
| `features/calendar/domain` | Event, recurrence, IANA timezone/DST behavior | Recurrence unit tests |
| `features/calendar/data` | Family/child/event repository, outbox, durable conflicts, reminders | Repository/sync tests |
| `features/calendar/presentation` | Progressive onboarding, Today/Week/Month, edit/assign/cancel/delete/conflict UI | Widget journey |
| `features/sync` | Version vectors, authenticated encryption, ordered upload/download | Two-device memory-relay test |

## Backend

| Module | Responsibility | Principal tests |
| --- | --- | --- |
| `api.auth`, `identity` | WebAuthn options/verification, hashed sessions, device replacement | Stage 2 API integration |
| `api.households`, `households` | Family ownership, child resources, invitations, memberships, permissions | Isolation/invitation/revocation integration |
| `api.sync`, `sync` | Encrypted operation relay, replay defense, grants, retention | Security/API integration |
| `db` | PostgreSQL connectivity and schema metadata | Migration integration |
| `core` | Configuration, auth dependency, errors, logging | Unit/security tests |

Stage 3 modules for AI proposals, email intake, notification change alerts, and
backup/recovery are intentionally absent.
