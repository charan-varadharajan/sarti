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

### BUG-003 — Child profile creation is local-only; cross-device child labels incomplete
- Severity: Medium
- Component: `mobile/lib/src/features/calendar/`, backend `api/households.py`
- Discovered: 2026-10-11
- Blocking: Stage 2 multi-device acceptance and therefore final Stage 3 acceptance
- Summary: The server has a child-resource endpoint, but mobile does not
  provision that resource, encrypt the child profile, or distribute its key.
  Child labels therefore do not appear on a second authorized device.
- Root cause: Mobile-side resource provisioning and key distribution for child
  profiles was not implemented in Stage 2/3.
- Workaround: Single-device use is unaffected.
- Latest information: Commit `487c163` accidentally bundled untested
  client-selected child-resource groundwork with documentation. The follow-up
  administrative audit removed that partial API change so BUG-003 can be fixed
  as one coherent, contract-tested implementation. The defect remains open.
- Required action: Complete and verify the missing Stage 2 child resource sync
  and key lifecycle before Stage 3 can be accepted.

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

### BUG-002 — Backup restore could not recover SQLCipher key on replacement device
- Severity: High
- Component: backup service, recovery UI/bootstrap, authenticated backup API
- Discovered: 2026-10-11
- Fixed: 2026-10-12 — fixing commit references BUG-002 (recorded below after commit)
- Fix version: Unreleased
- Disposition: Approved ADR-032 carries the SQLCipher key inside the independent
  recovery envelope. Explicit owner upload, automatic discovery after login,
  phrase confirmation, validated staged restore, and protected-key activation
  replace manual file transfer. Server storage is opaque, bounded, revisioned,
  and deleted on family deletion. SQLCipher, API isolation, storage-failure,
  transport, and widget tests pass. Physical replacement-phone validation is
  still required; future resource grants remain tracked separately in BUG-004.

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
