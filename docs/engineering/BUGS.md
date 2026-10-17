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

### BUG-005 — Optional cloud provider acceptance deferred
- Severity: Medium (optional feature; native/local path unaffected)
- Discovered: 2026-10-11; clarified 2026-10-14
- Implementation fixed: safe server-managed credential path, strict minimized
  request schema, explicit v3 consent/action, atomic caps and generated API under
  maintainer-approved ADR-037. Direct mobile Gemini SDK removed; default disabled.
- Blocking: Live cloud provider acceptance only, explicitly deferred by maintainer
  on 2026-10-14. No automatic cloud fallback, billing or family-data call enabled.
- Remaining action: Review eligible model/project and provider/audience/retention
  controls, then obtain separate activation/synthetic smoke authorization. Current
  2.5 adapter requires prior provider access; new projects need reviewed current
  model support. Mocks do not establish live compatibility.
- Verification: `../testing/REMAINING-BUGS-VERIFICATION.md` and
  `../api/CLOUD-ASSIST.md`. No reusable provider key is shipped in mobile.

---

## Resolved defects

### BUG-029 — Native prepared add-event test assumes the saved event is today
- Severity: Low; component: native calendar acceptance fixture
- Discovered: 2026-10-16 during final iOS regression
- Summary: CAL-MOB-001 reports missing Swimming when default start (now + one
  hour) crosses midnight; it checked today's agenda despite saving tomorrow.
- Cause: native fixture omitted the saved-date navigation already in its widget
  counterpart. Calendar persistence/recurrence assertions remain intact.
- Fix: navigate to the actual saved date before agenda assertions;
  assert that date rather than assume the current wall-clock day.
- Fixed: 2026-10-17; version 0.7.0+8; commit: this Stage 5 household milestone.
- Verification: native calendar group eight pass on both platforms; all nine native
  journeys/107 checks each pass. No production behavior/API/schema/security change.
- Disposition: Resolved for automated acceptance; see household verification report.
- Workaround: run the old scenario away from midnight; not needed after correction.


### BUG-028 — Email suggestions lacked multi-household display binding
- Severity: High; component: encrypted email delivery / mobile proposal sheet
- Discovered: 2026-10-16 during Stage 5 multi-context security review
- Summary: a device authorized in A/B could see A's suggestion while using B;
  broad membership-only delivery also failed to exclude care-calendar-only roles.
- Cause: legacy single-household client had no sealed family binding/filter and
  gateway recipient checks used active membership without calendar resource rights.
- Fix: sealed email v2 binds family/suggestion IDs, API includes opaque
  family ID, client verifies/filter scopes and rejects stale selection. Gateway and
  listing require current household calendar read grant, suitable role and expiry.
- Fixed: 2026-10-17; version 0.7.0+8; commit: this Stage 5 household milestone.
- Verification: real PostgreSQL/crypto/UI isolation and final full regression pass.
- Disposition: Resolved for automated scope; caregiver sharing UI remains separate.
  See `../testing/STAGE-5-HOUSEHOLDS-VERIFICATION.md`.
- Workaround: do not enable multi-household email with older builds. Unbound v1
  deliveries fail closed in the new client; expired legacy mail needs resubmission.


### BUG-027 — Guardian local identity was limited to one household
- Severity: High; component: SQLCipher guardian profiles and pickup references
- Discovered: 2026-10-16 during Stage 5 additional-household/recovery integration
- Summary: the same enrolled adult ID could not appear in two local household
  profiles; original pickup foreign keys were not household-qualified.
- Cause: legacy single-household guardian primary key and global ID scope checks.
- Fix: local v12 composite household/guardian identity and matching
  pickup/dropoff foreign keys, scoped handoff/upserts, transactional migration.
- Fixed: 2026-10-17; version 0.7.0+8; commit: this Stage 5 household milestone.
- Verification: actual encrypted legacy migration/rollback, same-adult scopes,
  foreign pickup denial, all regression/native/build gates pass.
- Disposition: Resolved for automated scope; invalid legacy data fails closed.
  See `../testing/STAGE-5-HOUSEHOLDS-VERIFICATION.md`.
- Workaround: do not rely on multiple households with pre-v12 mobile builds.


### BUG-026 — Lost household access can block another household's pending uploads
- Severity: High; component: multi-context synchronization / uncertain receipts
- Discovered: 2026-10-16 during Stage 5 multi-household integration
- Summary: an interrupted upload retains the device's next sequence; losing write
  authority before retry prevented unrelated households from uploading.
- Cause: strict global sequence correctly prevented silent renumbering, but lacked
  explicit receipt reconciliation and local preservation of unavailable intent.
- Fix: own-device metadata-only receipt review after lost write access,
  explicit local quarantine preserving original payload/vector/envelope, then use
  server high-water mark for unrelated uploads. Expired receipts remain unknown.
- Fixed: 2026-10-17; version 0.7.0+8; commit: this Stage 5 household milestone.
- Verification: real PostgreSQL/security, exact crypto retry/receipt/quarantine,
  all regression/native/build gates pass.
- Disposition: Resolved for automated scope. Quarantined work stays protected;
  automatic re-publication is not offered. See household verification report.
- Workaround: retain pending work and avoid manually clearing/renumbering it.



### BUG-025 — Legacy invitation paths could inherit or broaden scoped authority
- Severity: High; component: membership re-enrollment and invitation approval
- Discovered: 2026-10-16 during Stage 5 scoped-role security review
- Summary: a revoked administrator's membership row retained its role on a new
  ordinary invitation; a partial administrator could approve grants outside its
  own resource authority through the legacy approval path.
- Cause: legacy flows assumed all owners held every public resource and revoked
  members could only have the guardian role.
- Fix implemented: reset re-enrollment to pending ordinary guardian with cleared
  expiry; require grant authority on each approved resource. This does not replace
  the still-pending Stage 5 step-up/audit integration for legacy mutations.
- Fixed: 2026-10-16; version 0.6.0+7; commit: this Stage 5 foundation commit.
- Disposition: Resolved for automated scope; final backend and native regression pass.
- Tests: test_context_administration.py proves removed-admin re-entry cannot regain
  administration and omitted-child approval is denied; authorized approval works.
- Workaround: do not enable scoped multi-admin roles with older backend versions.


### BUG-024 — Whole-family backup authorization for scoped administrators
- Severity: High; component: backend encrypted backup authorization
- Discovered: 2026-10-16 during approved Stage 5 role integration
- Summary: the legacy owner-only check would permit a newly scoped administrator
  to request a whole-family snapshot despite missing a child's resource grant.
- Cause: whole-family snapshot boundary assumed one broadly authorized owner.
- Fix implemented: require current read authority for every live public resource
  before whole-family backup read/upload/delete; private snapshots remain author-
  scoped. No plaintext or server-held recovery key is introduced.
- Fixed: 2026-10-16; version 0.6.0+7; commit: this Stage 5 foundation commit.
- Disposition: Resolved for automated scope; final backend and native regression pass.
  Shipping multi-admin administration UI remains pending separately.
- Tests: test_context_administration.py covers omitted-child snapshot read/upload/
  delete denial, preserved original snapshot, admin/audit/resource isolation.
- Workaround: do not promote partial administrators on older backend versions.



### BUG-023 — Profile navigation and event-entry usability
- Severity: Medium; component: mobile presentation/bootstrap
- Discovered: 2026-10-14
- Summary: guardian action disabled without explanation/action; combined people/
  pets destinations, missing Add adult, technical colour labels, unclear automatic
  aliases, minutes-only duration, verbose end time and no FAB Describe option.
- Cause: session-gated callback and minimal first-pass presentation; blank aliases
  already generate securely in the repository, but helper copy was unclear.
- Workaround: configured passkey-authenticated build for invitations, top-bar AI
  entry, calculate elapsed minutes manually.
- Fixed: 2026-10-14; version 0.5.1+6; commit: this BUG-023 remediation commit.
- Disposition: Resolved for automated scope. Separate profiles/actions, plain color
  copy, automatic-alias guidance, secure guardian/sign-in entry, FAB Describe,
  hours/minutes and compact date/DST-aware end previews.
- Verification: Flutter 221 pass/2 explicit HTTP skips, 36 prepared native checks
  per platform, normal APK/unsigned iOS builds and static/unit/security/audit gates
  pass. See `../testing/BUG-023-VERIFICATION.md` for exact checks and exclusions.
- Remaining limitation: Physical connected invitation/passkey acceptance; offline
  installations still need configured service before issuing invitations/removal.
- Boundaries: ADR-035/038 adult invitations still require authenticated service;
  offline membership is never fabricated. ADR-036 excludes stored aliases from
  optional cloud payloads; aliases do not guarantee anonymity.


### BUG-021 — Family management hub
- Severity: Medium
- Fixed: 2026-10-14; version 0.5.0+5; commit: this combined remediation commit
- Disposition: Unified owner-aware Family screen, encrypted family/guardian/child name editing, existing guardian/removal, pastel profile and retention routes; offline/access guidance.
- Verification: `../testing/REMAINING-BUGS-VERIFICATION.md` (executed results and
  physical/provider/CI limitations). No next stage or cloud activation.

### BUG-017 — Obsolete remote conflict cards
- Severity: Medium
- Fixed: 2026-10-14; version 0.5.0+5; commit: this combined remediation commit
- Disposition: Persisted vectors are authoritative; retire only same-event conflicts covering both parents, reject stale cards and prevent stale snapshots reopening them.
- Verification: `../testing/REMAINING-BUGS-VERIFICATION.md` (executed results and
  physical/provider/CI limitations). No next stage or cloud activation.

### BUG-014 — Persistent unsafe Undo
- Severity: Medium
- Fixed: 2026-10-14; version 0.5.0+5; commit: this combined remediation commit
- Disposition: Five-second closable feedback opens review instead of deleting; explicit Delete/Cancel/valid dirty Save, reverted/stale checks and safe dialog lifecycle.
- Verification: `../testing/REMAINING-BUGS-VERIFICATION.md` (executed results and
  physical/provider/CI limitations). No next stage or cloud activation.

### BUG-013 — Single-proposal parsing and duration gaps
- Severity: Medium
- Fixed: 2026-10-14; version 0.5.0+5; commit: this combined remediation commit
- Disposition: Multiple reviewed clauses save atomically; noon/midnight, explicit durations/end ranges, visible editable defaults and end previews including DST clarification.
- Verification: `../testing/REMAINING-BUGS-VERIFICATION.md` (executed results and
  physical/provider/CI limitations). No next stage or cloud activation.

### BUG-012 — Native iOS scenarios absent from CI
- Severity: Medium
- Fixed: 2026-10-14; version 0.5.0+5; commit: this combined remediation commit
- Disposition: Main/PR CI now runs eight allowlisted prepared journeys with runtime discovery, per-scenario summary and failure logs/screenshots; portability excluded.
- Verification: `../testing/REMAINING-BUGS-VERIFICATION.md` (executed results and
  physical/provider/CI limitations). No next stage or cloud activation.

### BUG-022 — Family recovery drops historical decryption/causal continuation
- Severity: High
- Discovered/fixed: 2026-10-13
- Fix version: 0.4.0+4; fix commit: this BUG-022 implementation commit
- Disposition: Approved ADR-040 preserves validated family history and quarantined
  intent. Fresh authority/current grants, download-only catch-up and explicit
  review gate new-device publication and retention resume. Former credentials
  and envelope bindings reset. Completed intent bodies are removed; incomplete
  legacy history stays readable and blocked. No private-access or completeness
  guarantee is introduced.
- Verification: Flutter 202 pass/2 opt-in skips (both HTTP hosts executed);
  backend 33 pass, 91.51% coverage; native recovery 15 pass each on iOS/Android.
  Static, migration, dependency, tooling, Docker/health and secret checks pass.
  See `../testing/BUG-022-VERIFICATION.md` for exact results/security boundaries.
- Remaining limits: Physical passkeys/protected storage/provider lifecycle,
  previously stripped backups and history beyond relay TTL; personal pending-write
  continuation is not claimed. Android→iOS portability was not run.

### BUG-020 — Optional guided family setup
- Severity: Medium; fixed in 0.2.0+2 (2026-10-13).
- Fix commit: `12a3c21`; implementation candidate was d056258.
- Disposition: Optional names/Skip setup, optional children, named colours and
  access checks preserve progressive onboarding. Failed drivers now settle
  rebuilds and scroll to real targets without relaxing assertions.
- Verification: Full Flutter 169 pass/2 opt-in skips; seven family setup cases,
  prepared calendar and child sync pass on iOS/Android. Physical retest remains.
  See `../testing/BUG-020-VERIFICATION.md` and ADR-038 verification.

### BUG-015 — Child-specific selectable calendar colours
- Severity: Medium; fixed in 0.2.0+2 (2026-10-13).
- Fix commit: `12a3c21`.
- Disposition: Named pastel choices, unused new-child defaults, explicit reuse
  when exhausted, and owner-controlled correction of old colours with encrypted
  causal updates. Upgrade never silently recolours old records. Shared events
  use a primary profile colour plus complete participant labels/tooltips; larger
  child blocks also show individual avatars.
- Verification: Two-child/choice/exhaustion and encrypted-receiver cases pass;
  PROFILE-CHILD-001 proves deliberate legacy recolouring on both native platforms.
  Full Flutter 169 pass/2 skips; physical accessibility/user acceptance remains.
  See `../testing/ADR-038-VERIFICATION.md`.


### BUG-018 — Today segment does not return to the current date
- Severity: Medium
- Component: Calendar range selector / Kalender navigation
- Discovered: 2026-10-13, maintainer physical-iPhone testing
- Fixed: 2026-10-13 — Unreleased
- Disposition: Repeatable Today intent jumps to the current configured-zone date,
  including when already selected; agenda state is retained. Toolbar navigation
  keeps Week/Month layouts. No persistence or permission policy changes.
- Verification: Analysis, full Flutter suite (151 passed, 2 opt-in skips) and
  iOS/Android native grid + Today suites (10 each) PASS. Physical retest pending.
  See `../testing/BUG-018-VERIFICATION.md`.
- Summary: Tapping Today does not jump back to the current day.
- Evidence: The Today segment selects the single-day layout; range changes keep
  `_selectedDay`. A separate Go to today icon owns current-date navigation.
- Workaround: Use the Go to today calendar icon; physical result unverified.

### BUG-019 — First family creation leaves event/child controls hidden
- Severity: High
- Component: Authenticated calendar bootstrap / permission presentation
- Discovered: 2026-10-13, maintainer physical-iPhone testing
- Fixed: 2026-10-13 — Unreleased
- Disposition: Bootstrap listens to calendar controller changes and recomputes
  existing role checks after family creation; no permission policy change.
- Verification: Analysis and full Flutter suite PASS (144 passed, 2 opt-in skips).
  Four prepared bootstrap regressions cover fresh/existing owners, read-only and
  revoked guardians. Physical-phone rebuild/retest remains unexecuted.
  See `../testing/BUG-019-VERIFICATION.md`.
- Summary: Calendar opens after Create family but Add Event is absent.
- Evidence: Bootstrap computes canWrite/canManageChildren before a family exists;
  only the nested CalendarScreen listens to controller notifications. The outer
  permission properties are not recomputed when the first family is created.
- Workaround: Restart the app after creating the family, allowing fresh permission
  evaluation. This is source-derived and not physically verified.

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
