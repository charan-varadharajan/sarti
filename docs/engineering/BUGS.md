# Known defects

This file is the single source of truth for open and recently resolved defects.
It is not a substitute for a full issue tracker but serves as the binding
in-repository record while Sarti has no external tracker.

## Maintenance rules (binding — enforced by AGENTS.md)

- Every newly discovered defect gets the next `BUG-NNN` ID. IDs are never reused.
- Open defects must have: ID, severity, component, summary, root cause (if known),
  workaround (if any), blocking status, and discovery date.
- When a defect is fixed: move it to the Resolved section, add fix version,
  fix commit, and a one-line disposition. Do not delete resolved entries.
- When a defect is closed as won't-fix or deferred: note the decision and date.
- Update the open defect's entry whenever new information is available — do not
  create duplicate entries.
- Reference `BUG-NNN` in commit messages and `CHANGELOG.md` entries that fix it.
- Severity levels: **Critical** (data loss / security breach), **High** (feature
  broken, no workaround), **Medium** (feature degraded, workaround exists),
  **Low** (cosmetic / minor inconvenience).

---

## Open defects

### BUG-017 — Remote resolution leaves an obsolete conflict card open
- Severity: Medium
- Component: calendar repository conflict lifecycle
- Discovered: 2026-10-12 during BUG-011 source review
- Blocking: Complete cross-device conflict-resolution UI acceptance
- Summary: Receiving a causally newer resolution updates the event but does not
  retire the receiver's earlier conflict row. Its alternatives remain preserved,
  but the old conflict can still be offered for action.
- Evidence: `_saveRemote` writes event/version/applied-operation state without
  updating `conflicts`; only the locally invoked `resolveConflict` retires a row.
- Workaround: Review the latest event before acting on an old conflict card.
- Required action: Define causal retirement of superseded conflict rows and test
  remote resolution/stale-card actions. Deferred from BUG-011; no fix included.

### BUG-015 — Every child added through the app receives the same colour
- Severity: Medium
- Component: `features/calendar/presentation/calendar_screen.dart`, child profiles
- Discovered: 2026-10-12 during maintainer simulator testing
- Blocking: P0 child-specific colour-coded schedule acceptance
- Summary: Multiple children have identical calendar colour indicators.
- Root cause: The add-child UI hardcodes `0xFF8E6CEF` for every new profile;
  there is no colour selection or distinct default assignment.
- Workaround: None through the shipping child UI; review child assignments
  explicitly rather than relying on colour.
- Proposed action: Choose distinct defaults from an accessible palette using
  existing household colours, and let parents choose a colour before creation.
  Keep names/labels alongside colour; handle palette exhaustion explicitly.
  Existing duplicate-colour profiles need a deliberate correction path that
  preserves encrypted synchronization semantics; do not silently recolour only
  one device. Calendar currently shows the first assigned child's colour for
  shared events; define clear indicators for multiple children as part of design.
  Add prepared two-child widget/native tests, persistence/encrypted-delivery
  checks and shared-event/palette edge cases. Pending implementation; no tests run.

### BUG-014 — Event-added Undo action persists indefinitely
- Severity: Medium
- Component: `features/calendar/presentation/calendar_screen.dart`
- Discovered: 2026-10-12 during maintainer simulator testing
- Blocking: Safe transient post-save feedback; stale Undo can delete an event
  after the parent considers the save complete.
- Summary: The "Event added" snackbar remains visible with an active Undo link.
- Root cause: The pinned Flutter 3.47.7 SDK defaults `SnackBar.persist` to true
  when an action is present. Sarti supplies an Undo action without overriding
  persistence. SDK source confirms this; no tests executed for this report.
- Workaround: Dismiss the snackbar by swiping it away; avoid the stale Undo link.
- Proposed action: Make standard feedback transient (five-second Undo window),
  provide an explicit close control, and replace old feedback when another event
  is saved. Preserve screen-reader accessibility behavior rather than forcing
  timers that make the action inaccessible.
- Approved interaction (2026-10-12): Tapping Undo opens an editable preview of
  the saved event; it must not immediately delete or modify it. The preview has
  Delete, Cancel and Save. Delete explicitly deletes that event. Cancel closes
  the preview and discards unsaved edits, leaving the saved event intact. Save
  starts disabled and enables only for valid changes from the original event;
  reverting every change disables it again. Save persists reviewed changes.
  Dismissing the preview without saving behaves like Cancel. If the event no
  longer exists, handle that safely rather than recreating it from stale data.
  This supersedes the previously proposed immediate-Undo deletion behavior.
- Required regressions: Snackbar expiry/close without mutation; Undo opens
  preview without a write; Delete removes only the target; Cancel/dismiss
  preserves it; Save dirty/valid/reverted state and persistence; consecutive
  saves target the correct event; stale/deleted event and accessibility cases.
  Pending implementation; separate from BUG-013 parsing/duration work.

### BUG-013 — Multi-event natural-language input is reduced to one proposal
- Severity: Medium
- Component: `features/ai/event_parser.dart`, `natural_language_event_dialog.dart`
- Discovered: 2026-10-12 during maintainer simulator testing
- Blocking: Reliable natural-language entry of multiple independently timed events
- Summary: A sentence describing the same activity for two children at different
  times produces only one entry. Synthetic reproduction: "Tomorrow karate for
  Alex at 5 pm and Sam at 7 pm."
- Root cause: `AiProvider.parse` returns a single `EventProposal`; deterministic
  time extraction uses the first match and the review/save UI owns one event.
  Native enrichment also feeds the single-proposal review path.
- Workaround: Enter and approve each child's event separately, checking the
  date, time and child assignment in each preview.
- Proposed action: Detect multiple event clauses; present separate editable
  proposals with explicit confirmation and undo. Carry shared date/activity only
  when unambiguous; require clarification otherwise. Never silently discard a
  clause or create an event automatically. Add parser, review/approval, no-write
  before approval, ambiguity and prepared native UI regressions. Pending design
  review; no implementation or test execution yet.
- Approved duration requirement: When the input specifies no end time or
  duration, each proposed event defaults to 60 minutes. Show an editable
  "Duration: 1 hour (default)" in each preview before approval. This is an app
  default, not an inferred fact. Explicit end times/durations must be honored
  when unambiguous and valid; unclear or conflicting values require clarification.
  Current natural-language save hardcodes 60 minutes without an editable duration.
  Include tests for visible defaults, independent per-proposal edits, explicit
  durations/end times and confirmation preserving the reviewed duration.
- Additional reported case: Named clock times are not recognized by the
  deterministic parser, which handles numeric times only. Synthetic regression:
  "alex has swimming for 2 hours tomorrow at noon" must propose swimming for
  the matched child tomorrow at 12:00, duration 120 minutes, ending at 14:00,
  subject to explicit approval. Parse noon as 12:00 (not midnight), keep the
  duration separate from the start time, and remove recognized scheduling words
  from the event title. Add deterministic-parser and editable-preview/save
  regressions so the case works without native AI. Not fixed or tested yet.
- Calendar display gap: Event subtitles display only the start time even though
  events persist `durationMinutes`; the manual event editor also has no duration
  control. Show start and end in calendar entries and review/edit flows, with
  editable duration/end time for manual as well as natural-language creation.
  Derive the displayed end from the stored start, event timezone and duration;
  handle crossing midnight with an end-date indication and cover DST boundaries.
  Preserve existing event durations on edit. Add prepared widget/native
  regressions for one-hour defaults, two-hour entries, edits and overnight/DST
  ranges. No implementation or test execution yet.

### BUG-012 — iOS simulator integration tests are absent from CI
- Severity: Medium
- Component: `.github/workflows/ci.yml`, `mobile/integration_test/`
- Discovered: 2026-10-12
- Blocking: Automated native iOS regression coverage; a green CI build alone
  does not establish simulator journey acceptance.
- Summary: The iOS job compiles the app but never boots a simulator or executes
  integration tests. Flutter unit/widget tests run on Linux in the Android job.
- Root cause: Simulator integration execution and result reporting were not
  added to the workflow.
- Workaround: Run the prepared native scenarios locally when required; report
  those results separately from CI builds.
- Required action: Add prepared-fixture iOS simulator integration tests on PRs
  and main pushes, with readable results and failure artifacts. Preserve the
  explicit instruction not to run Android-to-iOS backup scenario
  `BACKUP-XPLAT-002` until separately authorized. Pending; no CI change yet.

### BUG-005 — Optional Gemini adapter is not connected to a safe shipping credential path
- Severity: Medium
- Component: `mobile/lib/src/features/ai/`, backend configuration, ADR-023
- Discovered: 2026-10-11
- Blocking: Optional Gemini provider acceptance; local/native parsing is unaffected
- Summary: The mobile Gemini adapter and consent gate exist, but the shipping
  bootstrap constructs only the native provider. `SARTI_GEMINI_API_KEY` exists
  only in backend settings and is unused there; it cannot configure the mobile
  adapter. Embedding an unrestricted provider key in the app would expose it.
- Root cause: Provider credential delivery and runtime construction were not
  designed end to end.
- Workaround: Cloud assist remains unavailable; deterministic and native
  on-device parsing continue without a cloud fallback.
- Approved privacy remediation (2026-10-13): ADR-036 replaces transmitted stable
  aliases/free-form prompts with fresh labels and a fail-closed structured token
  grammar, evidence-bound output and disclosure-v2 consent. UI/privacy/marketing
  guidance removes blanket “personal information never leaves your phone” claims.
  This does not wire cloud credentials or establish live provider compatibility;
  BUG-005 remains open for that integration. Automated results are recorded in
  `../testing/BUG-005-PRIVACY-VERIFICATION.md`.
- Required action: Approve a provider credential architecture that preserves
  ADR-036 minimization and explicit consent without exposing a reusable key,
  then implement and perform a live provider test.

---

## Resolved defects

### BUG-004 — Guardian invitation/approval not connected to shipping mobile journey
- Severity: Medium
- Component: Guardian mobile journey, household API and encrypted handoff
- Discovered: 2026-10-11
- Fixed: 2026-10-13 — implementation `820f42d`, targeted verification follow-up
- Fix version: Unreleased
- Disposition: Approved ADR-035 adds share/copy/QR invitations, explicit acceptance,
  pinned-device approval, resource permissions, cancellation/retry/removal,
  read-only UI and scoped encrypted current-state handoff. Migration 0007 records
  relay baselines. Follow-up repairs QR test API usage, test-engine initialization
  and the missing applied-operation timestamp that rolled back profile readiness.
- Verification: Analysis, full Flutter suite (136 pass, 2 opt-in skips), real
  HTTP/PostgreSQL/Dart handoff and prepared iOS/Android guardian journeys (3 each)
  PASS. Backend/migration/security, dependency, tooling, Docker health and shipping
  builds passed during implementation. Offline secret scan and version checks pass.
  See `../testing/BUG-004-VERIFICATION.md` for exact runs and limits.
- Remaining acceptance boundaries: Physical camera/link/share/passkey/protected
  storage and production two-phone validation remain unverified. No in-app QR
  scanner or universal-link landing page; compatible installed-app reader/paste
  fallback applies. No other bug or Stage 4 work was started.

### BUG-011 — PostgreSQL map ordering broke multi-author ciphertext authentication
- Severity: Medium
- Component: resource crypto, sync envelope and PostgreSQL relay
- Discovered: 2026-10-12
- Fixed: 2026-10-13
- Fix version: Unreleased
- Fix commits: `038acbe` (implementation), `3501330` (style/test spot fixes)
- Disposition: Approved ADR-034 introduces deterministic protocol-2 metadata,
  fixed field order and sorted version-map keys. Migration 0006 preserves legacy
  ciphertext with version 1. Exact retries include the version; legacy pending
  bytes are retained and unknown/tampered versions fail without fallback.
- Verification: Full backend/PostgreSQL and Flutter suites, real HTTP/PostgreSQL/
  Dart encryption/conflict regression, migrations, static/security/dependency
  checks, Docker startup/health, offline secret scan, OpenAPI/version checks PASS.
  See `../testing/BUG-011-VERIFICATION.md` for commands and limits.
- Remaining boundaries: Already-lost legacy map ordering needs authorized
  recovery; it is not guessed or discarded. Backend-first rollout and upgraded
  clients are required. Physical-device validation and BUG-017 are separate.

### BUG-010 — Device replacement did not advance resource-key epochs
- Severity: High
- Component: authentication, resource-key lifecycle and sync
- Discovered: 2026-10-12
- Fixed: 2026-10-12
- Fix version: Unreleased
- Fix commits: `c685fa1` (implementation), `a54ec74` (test setup/expectations)
- Disposition: Active-phone replacement atomically advances accessible live
  resource epochs with revocation and new device/session creation. Ordered
  resource locks serialize uploads/grants; stale new writes and revoked-device
  grants fail. Remaining/recovered admins establish fresh signed sealed keys
  without restoring old identity or silently replacing an established key.
- Verification: Full PostgreSQL/backend tests, migration checks, full Flutter
  tests, format/analysis, Ruff/Mypy/Bandit, dependency audit, offline pinned
  Gitleaks, OpenAPI drift and version checks PASS. See
  `../testing/BUG-010-VERIFICATION.md` for commands and limits.
- Remaining boundaries: Physical passkeys/protected storage, production recovery
  transport and two-phone tests remain release validation. Historical copies
  cannot be erased. No other bug or Stage 4 scope is included.

### BUG-016 — Day/week/month controls reused one agenda list without calendar grids
- Severity: Medium
- Component: calendar presentation
- Discovered: 2026-10-12
- Fixed: 2026-10-12
- Fix version: Unreleased
- Fix commit: `06e5837` (implementation); follow-up `test(calendar): correct BUG-016 verification expectations`
- Disposition: Approved ADR-033 pins Kalender 0.33.0. Day/week time grids,
  month grid, period/Today navigation, agenda, proportional event blocks,
  overlap layout and child/time labels use Sarti's scoped recurrence adapter.
  Widget create/drag/resize paths are disabled; edits retain explicit save flows.
- Verification: Initial failures were test expectations: use canonical `Etc/UTC`
  and repository alphabetical child order. Corrected only those expectations.
  Targeted tests 7/7, full Flutter suite 120/120, iOS grid 3/3 and Android grid
  3/3 pass. Static analysis and formatting pass. See
  `../testing/BUG-016-VERIFICATION.md` for exact results and limits.
- Remaining boundaries: Physical devices and screen readers unverified.
  BUG-013/014/015 and security/release blockers remain separate open defects.

### BUG-003 — Child profile creation was local-only; cross-device labels incomplete
- Severity: Medium
- Component: calendar repository/UI, authenticated sync/key exchange, resource/grant API
- Discovered: 2026-10-11
- Fixed: 2026-10-12
- Fix commit: `48d3b44`
- Fix version: Unreleased
- Disposition: Stable per-child resources, atomic encrypted local outbox,
  explicit owner sharing intent, signed recipient-bound sealed-key exchange,
  validated encrypted profile application, exact upload retries and safe
  calendar/profile ordering are implemented. Existing calendar guardians get
  read access only through explicit creation consent. Epoch rotation converges
  without silently replacing keys; revoked devices receive no future grants.
  SQLCipher v6 preserves profiles, assignments and queued writes.
- Verification: Unit/widget/transport/crypto, real PostgreSQL authorization and
  migration tests, and native iOS/Android prepared child-sync scenarios pass.
  See `../testing/BUG-003-VERIFICATION.md` for exact results and limits.
- Remaining boundaries: New-guardian onboarding is BUG-004; replacement-device
  epoch advancement is BUG-010. Physical-phone passkeys/protected storage and
  production transport remain acceptance checks. No Stage 4 authorization.

### BUG-002 — Backup restore could not recover SQLCipher key on replacement device
- Severity: High
- Component: backup service, recovery UI/bootstrap, authenticated backup API
- Discovered: 2026-10-11
- Fixed: 2026-10-12 — commit `cb08bc3`
- Fix version: Unreleased
- Disposition: Approved ADR-032 carries the SQLCipher key inside the independent
  recovery envelope. Explicit owner upload, automatic discovery after login,
  phrase confirmation, validated staged restore, and protected-key activation
  replace manual file transfer. Server storage is opaque, bounded, revisioned,
  and deleted on family deletion. SQLCipher, API isolation, storage-failure,
  transport, and widget tests pass. Physical replacement-phone validation is
  still required; future resource grants remain tracked separately in BUG-004.
- Verification update (2026-10-12): `BACKUP-XPLAT-001` passed real native
  iOS-simulator export to Android-emulator restore of the identical `.srtbk`,
  including wrong-phrase rejection and full fixture content/relationships.
  Passkeys, production relay and platform protected storage were excluded; see
  `../testing/BACKUP-PORTABILITY.md`.

### BUG-001 — Backup phrase was not BIP-39 conformant
- Severity: High
- Component: `mobile/lib/src/core/backup/backup_service.dart`
- Discovered: 2026-10-11
- Fixed: 2026-10-12 — commit `6b55cd1`
- Fix version: Unreleased
- Disposition: ADR-031 replaces the 256-word, checksum-free generator with
  `bip39_mnemonic` 4.1.0. New phrases use 128-bit libsodium entropy, standard
  BIP-39 English checksum validation, and official-vector coverage. Invalid
  recovery input fails before backup-key derivation or writing a restored file.
  The separate key-envelope defect is addressed by BUG-002 and ADR-032.

### BUG-009 — Prepared add-event scenario missed an off-screen child selector on iPhone
- Severity: Low
- Component: `mobile/integration_test/calendar_add_event_scenario_test.dart`
- Discovered: 2026-10-12 during iPhone 18 Pro simulator execution
- Fixed: 2026-10-12 — commit `3723ec0`
- Fix version: Unreleased
- Disposition: The scenario now scrolls the child selector into view before
  interaction, making the shared test work across Android and iPhone layouts.

### BUG-008 — Android device-key loading opened competing authentication prompts
- Severity: High
- Component: `mobile/lib/src/core/crypto/device_key_store.dart`
- Discovered: 2026-10-12 during Android API 35 emulator smoke test
- Fixed: 2026-10-12 — commit `4d2a96d`
- Fix version: Unreleased
- Disposition: Android still enforces device credentials for its hardware-backed
  protected storage key and Sarti still performs its explicit local unlock, but
  the plugin now caches the unlocked storage key for the app process instead of
  prompting separately for every field in the six-part device key.

### BUG-007 — Natural-language parser silently selected AM for ambiguous times
- Severity: High
- Component: `mobile/lib/src/features/ai/`
- Discovered: 2026-10-12 during Android API 35 emulator smoke test
- Fixed: 2026-10-12 — commit `4d2a96d`
- Fix version: Unreleased
- Disposition: Clock times from 1 through 12 without AM or PM now remain unset,
  the review UI requires the parent to choose the intended time, and model
  enrichment cannot bypass that confirmation.

### BUG-006 — Missing device credential exposed an internal unlock error
- Severity: Medium
- Component: `mobile/lib/src/features/calendar/presentation/stage2_bootstrap.dart`
- Discovered: 2026-10-12 during Android API 35 emulator smoke test
- Fixed: 2026-10-12 — commit `f4dedad`
- Fix version: Unreleased
- Disposition: The bootstrap now displays a bounded device-security explanation
  and retry action without exposing platform exception details or weakening the
  PIN/biometric requirement.

### BUG-000 — Email suggestions stored plaintext on server
- Severity: High
- Component: `backend/src/sarti_backend/api/email.py`, `db/schema.py`
- Discovered: 2026-10-11
- Fixed: 2026-10-11 — commit `4185410`
- Fix version: 0.1.0 (build 1)
- Disposition: Migration 0004 replaced plaintext `sender`, `subject_sanitized`,
  and `body_sanitized` columns with per-device libsodium sealed-box ciphertext.
  Server no longer stores readable email content. Mobile decrypts locally.

---

## Deferred / won't-fix

*(None yet.)*
