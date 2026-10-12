# Module catalog

## Developer tooling

`test` delegates to `scripts/run_tests.py`: Flutter unit/widget execution or
explicit prepared native calendar/child scenarios, automatic simulated-device
selection/startup, streamed logs and failure exit codes. No dependencies beyond
Python standard library and installed platform tools. Regression coverage is in
`scripts/test_run_tests.py`; added but not executed by the assistant per the
maintainer's test-ownership preference. Backup portability is excluded.

## Mobile

| Module | Responsibility | Principal tests |
| --- | --- | --- |
| `core/auth` | Native passkey adapter | Backend contract; physical platform pending |
| `core/crypto` | Device keys, secure storage, XChaCha20-Poly1305 resource content | Encrypted sync simulation |
| `core/backup` | BIP-39 validation, PBKDF2/XChaCha20-Poly1305 v2 envelope containing SQLCipher key | 15 phrase/envelope tests |
| `features/backup` | Encrypted consistent snapshot, owner upload/download/delete UI, staged recovery and protected-key activation | 7 SQLCipher/failure tests, 2 widget journeys; binary API transport test; `BACKUP-XPLAT-001` native portability scenario; reverse `-002` added, not run |
| `core/database` | SQLCipher verification, schema v1-v6, transactional migrations | Native engine and repository tests |
| `features/ai` | Deterministic parser, Apple/Android native bridge, strict proposal merge/review, local pseudonymization, versioned opt-in, and gated optional cloud adapter | Parser, native fallback/merge, approval/Undo widget, consent, and cloud-boundary tests |
| `features/calendar/domain` | Event, recurrence, IANA timezone/DST behavior | Recurrence unit tests |
| `features/calendar/data` | Atomic family/child/event repository, explicit child sharing intent, safe profile placeholders, outbox, durable event conflicts, reminders | Repository/sync tests |
| `features/calendar/presentation` | Progressive onboarding, Today/Week/Month, edit/assign/cancel/delete/conflict UI | Widget journey |
| `features/sync` | Version vectors, exact-envelope retries, authenticated child/calendar dispatch, signed sealed-key exchange and epoch convergence | Child sync/security/widget/native scenarios; PostgreSQL grant/relay contracts |
| `features/push` | FCM token lifecycle and strict opaque wake-up coalescing into encrypted sync | 6 coordinator unit tests; provider/device delivery pending |
| `features/email` | Device-addressed sealed-box decryption, source attribution, local proposal review, and device-scoped dismissal | Ciphertext/tamper unit tests and approval widget flow |
| `features/sync` authenticated runtime | Session restore, offline family provisioning, serialized encrypted sync, foreground catch-up, push lifecycle, and email refresh | Runtime and session-store unit tests; physical two-device run pending |

## Backend

| Module | Responsibility | Principal tests |
| --- | --- | --- |
| `api.auth`, `identity` | WebAuthn options/verification, hashed sessions, device replacement | Stage 2 API integration |
| `api.households`, `households` | Family ownership, child resources, invitations, memberships, permissions | Isolation/invitation/revocation integration |
| `api.sync`, `sync` | Encrypted operation relay, replay defense, grants, retention | Security/API integration |
| `api.email` | Cloudflare worker webhook, HMAC auth, injection sanitization, rate limit, deduplication, per-device sealed-box delivery, authenticated polling/dismissal, 7-day TTL | 8 email unit tests plus migration integration |
| `api.push` | FCM token registration, opaque sync_available wake-up to family devices | 3 push unit tests |
| `api.backups` | Owner/device-scoped opaque backup relay, 10 MiB limit, revision CAS, deletion | PostgreSQL API isolation/replay/deletion integration |
| `db` | PostgreSQL connectivity and schema metadata | Migration integration |
| `core` | Configuration, auth dependency, errors, logging | Unit/security tests |
