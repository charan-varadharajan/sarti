# Module catalog

## Developer tooling

`test` delegates to `scripts/run_tests.py`: Flutter unit/widget execution or
explicit prepared native calendar/child/grid/guardian scenarios, automatic simulated-device
selection/startup, streamed logs and failure exit codes. No dependencies beyond
Python standard library and installed platform tools. Regression coverage is in
`scripts/test_run_tests.py`. Assistant test execution follows the latest
maintainer instruction in CONTRIBUTING.md. Backup portability is excluded.

## Mobile

| Module | Responsibility | Principal tests |
| --- | --- | --- |
| `core/auth` | Native passkey adapter | Backend contract; physical platform pending |
| `core/crypto` | Device keys, secure storage, XChaCha20-Poly1305 resource content | Encrypted sync simulation |
| `core/backup` | BIP-39 validation, PBKDF2/XChaCha20-Poly1305 v2 envelope containing SQLCipher key | 15 phrase/envelope tests |
| `features/backup` | Encrypted consistent snapshot, owner upload/download/delete UI, staged recovery and protected-key activation | 7 SQLCipher/failure tests, 2 widget journeys; binary API transport test; `BACKUP-XPLAT-001` native portability scenario; reverse `-002` added, not run |
| `core/database` | SQLCipher verification, schema v1-v6, transactional migrations | Native engine and repository tests |
| `features/ai` | Deterministic parser, Apple/Android native bridge, strict proposal merge/review, ADR-036 request-scoped labels, fail-closed token grammar, evidence-bound cloud output, v2 opt-in, and gated optional cloud adapter | Parser, native fallback/merge, approval/Undo widget, consent, and cloud-boundary tests |
| `features/calendar/domain` | Event, recurrence, IANA timezone/DST behavior | Recurrence unit tests |
| `features/calendar/data` | Atomic family/child/event repository, explicit child sharing intent, safe profile placeholders, outbox, durable event conflicts, reminders | Repository/sync tests |
| `features/calendar/presentation` | Progressive onboarding, Today/Week/Month, edit/assign/cancel/delete/conflict UI | Widget journey |
| `features/calendar/presentation` grid adapter | ADR-033 Kalender day/week/month, range/Today navigation, selected-day and accessible agenda, occurrence duration/overnight/DST conversion; layout never writes | `calendar_occurrence_adapter_test.dart`, `calendar_grid_test.dart`, prepared native grid scenarios |
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

`households/device_replacement.py` exposes the metadata-only resource epoch
transition to authentication. Auth owns adult serialization/device/session
replacement; encrypted-sync writers share resource locks. Mobile
`ResourceKeySync` owns fresh keys and signed sealed grants, including unclaimed
advanced-epoch initialization after recovery. See KEY-MANAGEMENT.md and the
REPLACE scenario entries; no cryptographic primitive or wire format changed.

BUG-011/ADR-034 adds `resourceAdditionalData` as the shared deterministic v2 /
unchanged legacy encoder. Sync envelope persistence and HTTP transport carry the
version; backend relay models and migration 0006 persist it without plaintext
family content. `sync_metadata_test.dart` and the explicit
`test_sync_postgres_mobile.py` host cover legacy/security and real JSONB ordering.

## Guardian onboarding (BUG-004)

`features/guardians` owns strict memory-only invitation parsing/inbox,
coordinator state, device-code/resource review, share/copy/QR UI and retry/remove
flows. Authenticated bootstrap attaches one authorized local family, persists
read-only access, refreshes membership and wires the normal sync runtime.
`CalendarRepository` queues scoped handoff state and validates encrypted family
profiles; `ResourceKeySync` includes initial family-profile grant establishment.
Backend household APIs list/cancel/review invitations and enforce approval pins,
resource subsets, expiry and idempotency; sync reads enforce migration-0007
baselines. Prepared tests and real HTTP/PostgreSQL tests are listed in
TEST-SCENARIOS.md; no physical-provider behavior is inferred from test adapters.

BUG-019: `AuthenticatedCalendarBootstrap` listens to its calendar controller for
all controller-dependent presentation, including owner mutation controls and
family-dependent banners. First family creation no longer leaves cached false
permission properties on the child screen. Server authorization and encrypted
cached role checks are unchanged; prepared owner/read-only/revoked widget tests
cover the transition and no-write editor cancellation.

BUG-018: CalendarController issues repeatable, memory-only Today navigation
requests; CalendarScreen handles both new and already-selected Today activation.
FamilyCalendarView consumes requests in the configured timezone using an
injectable clock, without reconstructing agenda state. The toolbar icon still
keeps the chosen week/month layout. Navigation does not invoke local mutation,
reminders, synchronization or persistence. Shared Today scenarios run in the
widget and existing native grid suites.

BUG-020 implementation candidate: FamilySetupScreen owns optional name drafts and
an optional post-creation children step. ChildProfileEditor is shared with the
calendar action; it provides named colour choices, unused defaults, explicit
palette reuse, existing alias validation and opt-in profile sharing. It binds
saves to its starting family and the shared CalendarController.canManageFamily
predicate (the existing owner-cache policy, also used by bootstrap). Invalid
cache data fails closed. No resource/API/schema policy changes. Prepared family
and encrypted-delivery regressions are added; verification failures remain open.

## Adult/pet extension (ADR-038)

Calendar domain adds typed adult/pet references; repository owns personal resource
bindings, profile vectors and atomic shared copies. `household_profiles_screen`
provides own-adult/pet creation and explicit child colour edits. Calendar editor
separates Private from Save and share and supports exact-version household-copy
review. ResourceKeySync provisions personal/profile kinds without sharing personal
keys. Backend authorization and replacement modules enforce adult ownership;
backup modules partition and validate adult snapshots. No new dependency/service.

## Calendar retention (ADR-039)

`calendar_retention.dart` evaluates completion/period boundaries without I/O;
`calendar_retention_store.dart` is a repository part implementing atomic content
removal, minimized causal records and explicit conflict review.
`CalendarRetentionScreen` handles family scope, admin preview/confirmation and
conflict actions. Authenticated bootstrap refreshes policy after full catch-up,
sweeps at foreground sync and five-minute foreground intervals, then uploads
normal encrypted operations. The household API owns bounded preference metadata
and reuses membership/resource authorization; no new service/dependency.

## Family recovery continuation (ADR-040 / BUG-022)

`calendar_recovery_store.dart` validates scoped history, preserves/quarantines
intent and atomically maps explicit review to fresh outbox operations.
`FamilyRecoveryCoordinator` refreshes current authority/keys, catches up download
only, gates publication and validates history review before retention resume.
`FamilyRecoveryScreen` exposes prepared review/conflict/sharing/cleanup flows.
Bootstrap routes recovery through that coordinator, disables ordinary mutations
and prevents recreation. ResourceKeySync recovery mode skips private resources
and implicit provisioning; SyncEngine enforces exact reviewed-operation binding.

## Combined remaining-bug remediation (2026-10-14)

Parser `parseAll` preserves distinct clauses, explicit shared context, noon/
midnight and duration uncertainty. The dialog reviews each proposal and commits
all only after final approval; manual editor supports duration/end display and
safe dirty/stale preview state. Snackbar Undo is a transient review link, never
immediate deletion. Repository uses persisted vectors and retires only conflicts
whose two parents are causally covered. FamilyManagementScreen unifies existing
routes; name edits reuse encrypted profile kinds/authorization.

`ai.broker` / `api.ai` own strict token validation, atomic budgets and bounded
HTTPX provider processing; mobile gate holds no provider key and requires renewed
consent + explicit action. `scripts/ci_ios_tests.py` selects an available native
simulator, runs only allowlisted prepared journeys and emits results/artifacts.
