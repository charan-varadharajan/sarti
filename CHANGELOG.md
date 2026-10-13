# Changelog

All notable changes to Sarti are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [ADR-030](docs/architecture/adr/030-release-versioning.md) and
[SemVer](https://semver.org/). The canonical version is in `VERSION`.

## Maintenance rules (binding — enforced by AGENTS.md)

- Every version bump (`scripts/version.py bump`) must add an entry here in the
  same commit.
- Every bug fix must reference the `BUGS.md` defect ID it closes (e.g. `BUG-003`).
- Every security finding resolution must note the finding and its disposition.
- Entries are prepended (newest first). Do not edit past entries except to add a
  closed-bug cross-reference.
- Unreleased work accumulates under `[Unreleased]` until a version bump promotes
  it.

---

## [Unreleased]

### Added
- BUG-013 clarification: calendar entries omit end times and manual editing lacks
  duration controls; record start/end display and editable-duration requirements,
  preserving existing durations and handling overnight/DST ranges.
- BUG-013 clarification: record missing deterministic "noon" recognition and
  the two-hour swimming regression (12:00–14:00), including preview/save checks
  without native AI. Implementation remains pending.
- BUG-013 clarification: approved visible, editable one-hour duration defaults
  per proposal, with explicit end-time/duration handling and regression criteria;
  implementation remains pending.
- Record BUG-013 from manual simulator feedback: multi-event natural-language
  input is reduced to a single proposal; separate-entry workaround and proposed
  explicit multi-proposal review documented. Not fixed yet.
- Simple local test entry point: `./test`, `./test --ios`, and
  `./test --android`, with automatic simulator/emulator startup/selection,
  prepared calendar/child journeys, console pass/fail and ignored saved logs.
  Backup portability remains excluded; runner regression tests added, not run.
- Record BUG-012: pending native iOS simulator integration coverage in CI;
  current iOS job builds only. Document user-owned test execution and direct
  main pushes for the current remediation workflow.
- BUG-002 regression: add `BACKUP-XPLAT-002` for Android-to-iOS `.srtbk`
  recovery using the shared directional runner; execution deferred by user.
- BUG-002 regression: repeatable iOS-to-Android encrypted `.srtbk` portability
  scenario with native SQLCipher/libsodium, exact-byte transfer, prepared data,
  and explicit backup/restore UI actions.
- Repository-maintained changelog, known-defect register, contribution guide,
  draft privacy disclosure, and draft Cloud Run/Neon deployment runbook.
- Maintained functional scenario catalogue and a disposable Flutter fixture
  harness for prepared data, direct flow entry, emulator execution, and teardown.

### Corrected
- BUG-003: complete encrypted child-profile synchronization with stable resource
  IDs, atomic local writes, explicit read-only sharing for current calendar
  guardians, signed recipient-scoped sealed keys, verified epoch rotation and
  receiving-calendar labels/colours. Harden grant uniqueness/current authorization,
  resource-kind validation and filtered relay paging; persist exact upload retries.
  SQLCipher v6 and prepared unit/API/security/widget/native regressions included.
- BUG-002: connect v2 encrypted SQLCipher-key snapshots to an owner-authorized
  upload/download/delete API and reachable backup/recovery UI. Replacement
  installations discover backups after login, require the user-held phrase,
  validate family/integrity, and activate through a protected recovery journal.
- Fixed BUG-001: recovery phrases are now standard, checksum-validated BIP-39
  English mnemonics generated from libsodium entropy and checked before backup
  key derivation or restoration.
- Reviewed the new process documents against the accepted ADRs and current
  implementation; removed unsupported privacy/deployment claims and duplicate
  agent instructions.
- Removed incomplete, untested BUG-003 API groundwork that was accidentally
  bundled into the administrative commit. The complete BUG-003 fix above now
  supersedes that groundwork.
- Fixed BUG-006 so a missing device credential shows a bounded setup message and
  retry action instead of an internal `LocalAuthException`.
- Fixed BUG-007 so a time such as “Tuesday at 5” remains unset and asks the
  parent to choose AM or PM; native AI cannot silently resolve the ambiguity.
- Fixed BUG-008 so Android unlocks the protected secret-store key once per app
  process instead of opening competing prompts for each device-key field.
- Fixed BUG-009 so `CAL-MOB-001` scrolls a child selector into view before
  interacting with it on compact iPhone layouts.

### Known open defects
- BUG-011 (Medium): confirmed that PostgreSQL JSONB can reorder a multi-author
  version vector and invalidate insertion-ordered sync AAD. Canonical encoding
  and a real-backend conflict round-trip remain pending as a separate defect.
- BUG-010 (High): security review found that passkey device replacement revokes
  the old phone without advancing resource epochs. Recorded as a separate release
  blocker; implementation remains pending outside the BUG-003 child-sync fix.
See `docs/engineering/BUGS.md` for the current open defect list.
The administrative review added BUG-005 for the unwired optional Gemini
credential/runtime path.

---

## [0.1.0] — 2026-10-11 (build 1)

Stage 1 through Stage 3 implementation. First versioned snapshot. Not a public
release — private development baseline.

### Added — Stage 3 (2026-10-11)
- Deterministic NLP event parser; never fabricates fields (ADR-023)
- Native on-device AI bridges: Apple Foundation Models (iOS 26+) and Android
  ML Kit GenAI Prompt API 1.0.0-beta4, both runtime-gated with deterministic
  fallback (ADR-029)
- Local child/location pseudonymization before optional Gemini cloud assist;
  versioned opt-in consent gate (ADR-028)
- Cloudflare email ingress: HMAC worker-secret auth, injection sanitization,
  hashed routing token, rate limit, deduplication, 7-day TTL (ADR-024)
- Per-device libsodium sealed-box email encryption; migration 0004 replaces
  plaintext email columns with device-addressed ciphertext
- Mobile email suggestion inbox: authenticated polling, local decryption, source
  attribution, proposal review, post-approval dismissal
- Authenticated mobile bootstrap: secure session persistence, serialized
  encrypted sync, wake-up dispatch, email refresh, session expiry handling
- Opaque FCM push: token registration, `{"type":"sync_available"}` wake-up,
  OS-native notification sensitivity (ADR-026)
- PBKDF2-HMAC-SHA256 + XChaCha20-Poly1305 backup envelope with 12-word phrase
  (ADR-025) — **envelope exists; recovery format has open defects BUG-001 and
  BUG-002; backup UI not shipped**
- Repository-wide SemVer versioning, `VERSION`/`BUILD_NUMBER`, `scripts/version.py`,
  CI tag validation (ADR-030)
- Google Cloud Run + Neon Free selected for beta hosting (ADR-027)
- 76 Flutter tests, 21 backend tests passing; 87.17% backend branch coverage

### Added — Stage 2 (2026-10-11)
- Passkey registration/authentication, hashed sessions, one-active-phone policy
- Family ownership, guardian invitation/approval, resource permissions, revocation
- SQLCipher local storage, resource-scoped E2EE, encrypted relay, replay defense
- Offline outbox, version-vector conflicts, explicit conflict resolution
- Today/Week/Month calendar UI, recurring events, pickup assignment, reminders
- Migration 0002, OpenAPI contract, ADR-019 through ADR-022

### Added — Stage 1 (2026-10-11)
- Flutter/Riverpod + FastAPI/PostgreSQL foundation
- Docker Compose local environment, CI pipeline, structured errors, health endpoints
- Migration 0001, Ruff/Mypy/Bandit/pip-audit/Gitleaks gates

---

*Older entries will be added here as the project history is formalized.*
