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

### BUG-010 — Device replacement revokes access without advancing resource-key epochs
- Severity: High
- Component: `backend/src/sarti_backend/api/auth.py`, device/resource lifecycle
- Discovered: 2026-10-12 during BUG-003 security review
- Blocking: Release; ADR-020 replacement-device protection for future content
- Summary: Successful passkey authentication revokes existing devices/sessions
  and issues a new device ID, but does not increment affected resource epochs.
  A replaced phone retains old keys; later ciphertext using unchanged epochs
  remains decryptable if obtained outside the authenticated relay.
- Evidence: `authentication_complete` updates devices/sessions and creates the
  new device without updating resources. Existing replacement API tests prove
  old-session rejection, not cryptographic future-content separation.
- Workaround: No shipped cryptographic workaround. Keep device replacement out
  of release acceptance until rekeying is verified. Revocation does not erase
  earlier copies.
- Required action: Implement the accepted ADR-020 replacement transition with
  epoch advancement, remaining-device rekey/grants, interrupted-transition and
  stale-key tests. Preserve single-active-phone rules and recovery. This is a
  separate defect, not addressed by the BUG-003 child creation fix.

### BUG-011 — Multi-device version-vector order changes authenticated metadata
- Severity: Medium
- Component: `core/crypto/resource_crypto.dart`, sync AAD encoding, PostgreSQL relay
- Discovered: 2026-10-12 during BUG-003 security review
- Blocking: Real-backend concurrent calendar editing acceptance
- Summary: AAD uses insertion-ordered JSON, including the logical version map.
  PostgreSQL JSONB reorders that map. A legitimately relayed operation with
  multiple author entries can therefore fail AEAD authentication on download.
- Evidence: A synthetic real-PostgreSQL JSONB round trip changed vector order;
  PyNaCl/libsodium rejected ciphertext when AAD was rebuilt with the returned
  map. The Dart encryption/decryption paths use the same insertion-order rule.
  Existing memory-relay conflict tests preserve map order and miss this boundary.
- Workaround: Single-writer calendar operation vectors avoid this ordering case;
  do not treat concurrent editing as accepted against the real backend.
- Required action: Specify canonical AAD and legacy/version compatibility,
  obtain any necessary protocol/ADR approval, add a real HTTP/PostgreSQL mobile
  ciphertext round-trip regression, and preserve conflict alternatives. This is
  separate from immutable single-author child creation and is not fixed here.

### BUG-004 — Guardian invitation/approval not connected to shipping mobile journey
- Severity: Medium
- Component: `mobile/lib/src/features/`, backend `api/households.py`
- Discovered: 2026-10-11
- Blocking: Stage 2 multi-guardian acceptance and therefore final Stage 3 acceptance
- Summary: Guardian invitation and approval exist in backend and protocol tests
  but are not connected to a complete shipping mobile UI journey. A second
  guardian cannot be added through the app.
- Root cause: Mobile UI for invitation flow was not implemented in Stage 2/3.
- Workaround: Single-guardian families are unaffected.
- Required action: Complete and verify the Stage 2 mobile invitation, approval,
  resource-permission, and key-grant journey before Stage 3 can be accepted.

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
- Required action: Approve a provider credential architecture that preserves
  ADR-028 pseudonymization and explicit consent without exposing a reusable key,
  then implement and perform a live provider test.

---

## Resolved defects

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
