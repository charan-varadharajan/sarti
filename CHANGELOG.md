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
- Repository-maintained changelog, known-defect register, contribution guide,
  draft privacy disclosure, and draft Cloud Run/Neon deployment runbook.

### Corrected
- Reviewed the new process documents against the accepted ADRs and current
  implementation; removed unsupported privacy/deployment claims and duplicate
  agent instructions.
- Removed incomplete, untested BUG-003 API groundwork that was accidentally
  bundled into the administrative commit. BUG-003 remains open for a coherent
  implementation.
- Fixed BUG-006 so a missing device credential shows a bounded setup message and
  retry action instead of an internal `LocalAuthException`.

### Known open defects
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
