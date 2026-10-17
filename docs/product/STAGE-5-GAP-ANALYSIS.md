# Stage 5 — Repository review, baseline and gap analysis

Date: 2026-10-16. Reviewed source: f474a6f, development 0.5.1+6.
Status: assessment/design complete; Stage 5 implementation NOT complete.
Source: maintainer's Stage 5 attachment supplied 2026-10-16. Stop after Stage 5;
Stage 6 is not authorized. Hosting remains deferred until last.

## Review and reuse

Inventory: 367 nonignored files across mobile (178), backend (73), docs (101),
scripts/build/configuration and root instructions; .github CI was also inspected.
Reviewed architecture/index and ADR-001–040, security/threat/permission documents,
API descriptions and all 27 OpenAPI paths/36 schemas, database/migration designs,
testing/engineering instructions and STATUS. Focused code review covers auth/
WebAuthn/device storage, schema/migrations, households authorization/enrollment/
revocation, replacement epochs, mobile repository/bootstrap, guardian coordinator,
backup/setup UI and their integration/unit/widget/security tests. This is a
repository/module inspection, not a claim of exhaustive line-by-line verification
of every source file or physical platform behavior.

Reuse current crypto, passkeys/verifier, SQLCipher, opaque sessions, invitations/
QR, signed grants, current-epoch rotation, outbox/conflicts, backup v2/BIP-39,
protected recovery activation, retention and UI fixtures. Do not rebuild these.
Some older prose describes superseded blockers/versions; accepted ADRs and current
code/results take precedence over historical verification paragraphs.

Required named documents exist. No accepted 30-day deleted-event recovery policy
was found among ADR-001–040: treat it as this request's new product requirement,
not invent earlier approval. No Stage 5 implementation/scope document existed;
this review and its test plan are new. Newly requested school/classroom/role
capabilities were previously deferred. The current user request authorizes that
product scope, while accepted-ADR changes still need superseding design approval.

## Requirements classification

Implemented means current software behavior exists, not physical release approval.
Partially implemented includes working reusable infrastructure with missing
requested flow. Conflicting means an accepted decision must change, not that the
new requested behavior may be silently substituted.

| Requirement | Status | Current evidence / remaining work |
| --- | --- | --- |
| Registration without email/phone/real name | Implemented | auth.py registration bodies have no contact/name fields; adults table stores UUID/public metadata only |
| Opaque account/session IDs and minimal metadata | Implemented | UUID adults, secure random challenges/tokens, hashed session tokens |
| Role-neutral registration | Partially implemented | Account rows have no role; authenticator label is parent-UUID rather than neutral account label |
| Device-generated keys and SQLCipher initialization | Implemented | DeviceKeyStore, PlatformSecretStore/user-presence gate, SQLCipher engine verification; physical hardware guarantees unverified |
| Native passkey registration and device binding | Partially implemented | Native adapter and verified backend flow exist; physical ceremonies/RP configuration still pending |
| Duplicate registration/device abuse | Partially implemented | Credential uniqueness/challenge replay/one-active-device controls exist; dedicated race/retry/key-reuse policy and coverage need expansion; cannot deduplicate real people without identity data |
| Context-specific simultaneous roles | Missing | Only owner/guardian membership roles; no education/caregiver context model |
| Temporary invitations, QR, expiry/revocation, explicit approval | Implemented | ADR-035 GuardianScreen/coordinator + household API; physical delivery limits remain |
| Multiple household administrators | Conflicting | ADR-022 single owner; require_owner and schema role constraint; no promote/demote flow |
| Child-specific profile access | Implemented | Explicit child resource grants, independent keys and hidden placeholders |
| Child-specific schedule/guardian access | Partially implemented | Profile separation exists; shared household calendar still reveals all granted calendar content |
| Limited caregiver access | Missing | Granting whole-calendar key with UI filtering would leak other appointments |
| Adult in multiple households | Partially implemented/conflicting | Backend composite membership key supports multiple families; mobile LIMIT 1/enrollment/single-family backup prevent complete journey |
| Child in multiple authorized households | Missing | Each child/resource has one family scope; explicit separately authorized representations/link semantics needed |
| Independent membership removal | Partially implemented | Backend removes target family permissions/rotates family epochs; multi-context client/key isolation must be completed |
| Prevent last-admin removal | Partially implemented/conflicting | Existing endpoint only removes guardians, not owners; multi-admin concurrent demotion/leave/delete invariant absent |
| Guided phrase generation and encrypted backup/restore | Implemented | BIP-39, independent snapshot keys, v2 encrypted relay, own private scope, protected activation and recovery review |
| Recovery confirmation during onboarding | Missing | Backup screen has saved-words acknowledgement; no onboarding phrase challenge/confirmation flow |
| Phone replacement and old-device revocation | Implemented | Atomic epoch advance/device/session replacement with real PostgreSQL concurrency tests; physical ceremony pending |
| Guardian-assisted family access recovery | Partially implemented | Verified new-device scoped enrollment/handoff reusable; no dedicated lost-access recovery journey; cannot recover old identity/private keys by guardian approval |
| Admin removal and changing child guardianship grants | Missing | Sensitive promotion/demotion/delegation and operation-bound step-up absent |
| Membership revocation safeguards | Partially implemented | Owner-only current-device checks/epoch rotation exist; no operation-bound fresh-auth preview/audit flow |
| Household closure/account deletion | Missing | FK/soft-delete backup purge hooks and usage cleanup tests exist, but no complete authorized API/UI/job workflow |
| Authorized export | Partially implemented | Encrypted family/personal snapshot APIs exist; scoped multi-context export/privacy confirmation needs completion |
| Restore accidentally deleted events for up to 30 days | Missing/conflicting | No restore UI/expiry contract; ADR-039 removes expired content and must not silently gain 30-day hidden retention |
| Encrypted access-controlled sensitive-action audit | Missing | Sanitized operational logging is not encrypted user-visible audit history |
| Future-access revocation and key rotation | Implemented foundation | Current grants/epochs/device/permission checks; new scopes/expiry/narrowing must rotate affected resources only |
| Full Stage 5 tests | Missing | Existing tests cover old flows only; new 17-case traceability/test plan is planned, not executed |

## Baseline actually executed

No runtime edits were made before this baseline. Output is saved to ignored
`test-results/stage5-baseline-*`; successful logs were used only for runner
status/counts. No failures required investigation.

| Check | Result |
| --- | --- |
| Alembic upgrade on isolated sarti_stage5_baseline_test | PASS: 0010 head |
| Full backend Pytest, real PostgreSQL, both enabled HTTP/Dart contract hosts | PASS: 57 tests; total coverage reported 91% |
| Full Flutter unit/widget/SQLCipher/crypto/security suite with coverage | PASS: 221; 2 opt-in skips in this invocation, both executed through backend contract hosts |
| Flutter analyze | PASS |
| Ruff format/lint, strict Mypy, Bandit | PASS: make backend-check |
| Repository version integrity | PASS: 0.5.1+6 |
| Existing repository tooling tests | PASS: unittest discovery, 11 tests |

Backend commands: `.venv/bin/python -m alembic upgrade head`,
`.venv/bin/python -m pytest --cov --cov-report=term-missing -q` from backend with
SARTI_ENVIRONMENT=test, isolated SARTI_DATABASE_URL and both
SARTI_RUN_MOBILE_CONTRACT=1 / SARTI_RUN_GUARDIAN_CONTRACT=1. Runtime secrets came
from local .env internally and were not printed. The throwaway test database is
separate from development data. Flutter: `flutter test --coverage --reporter json`
and `flutter analyze`; repository: `make backend-check`, version.py check and
`python3 -m unittest discover -s scripts -p 'test_*.py'`.

Not rerun for this architecture-only assessment: native simulator/emulator
journeys, normal platform builds, live providers/physical passkeys, fresh dependency
advisory scan, Docker image rebuild, cross-platform backup transfers. No new
runtime/dependency/API/schema change. Prior native/build results are historical,
not fresh Stage 5 acceptance. Android-to-iPhone transfer/live Gemini activation
remain explicitly deferred. Full code-change regression remains mandatory after
implementation, including all native/contract/security/migration gates.

## Security and dependency findings before coding

1. Caregiver profile ACLs do not protect whole-calendar ciphertext. Need scoped
   scheduling copies/keys, not filtering after decryption or reusing family keys.
2. Multi-household query/context/cursor/backup scope must be explicit everywhere.
   Global server device sequence versus local family sequences needs one scheduler;
   simply switching UI families risks replays, lost writes and cross-family export.
3. Multi-admin removal races and role escalation require transactional current
   authorization plus a last-admin invariant; guardian admin-calendar permission
   is not currently household ownership.
4. Existing authentication/complete replaces the phone. Do not reuse it blindly
   for sensitive-operation reauthentication; use current-device-bound step-up.
5. Guardian-assisted recovery cannot become account impersonation/private recovery
   or an owner-backup bypass for restricted recipients.
6. Thirty-day restore conflicts with one-week default retention if implemented as
   hidden retained content. Hard deletion/closure/retention overrides must be explicit.
7. Duplicate-human detection without contact/identity data is not promised.
8. Audit ciphertext cannot prove a malicious client's narration is true; server
   operational outcome/ACL revision remains independently authoritative.
9. Production passkey/protected-storage/provider, legal guardianship/teacher identity
   and provider-backup erasure guarantees are not established by these tests.

No new dependency selected or installed. Reuse pinned WebAuthn/passkeys, sodium/
PyNaCl, SQLCipher, Alembic/SQLAlchemy/PostgreSQL and existing notification/QR/link
adapters. Review any necessary new dependency against maintenance, license,
advisories and platform privacy before adoption; no custom cryptographic primitive.
Existing Android native and opt-in HTTP-host CI automation gaps remain recorded
in P1-VOICE-TEST-PLAN; they must not be advertised as already closed.

## Reviewable next action and deliverable status

[Proposed ADR-041](../architecture/adr/041-stage5-scoped-membership-and-sensitive-operations.md)
resolves the accepted-ADR conflicts with explicit context grants, multi-admin/
multi-household state, scoped caregiver copies, step-up, assisted family access,
audit, deletion/export and retention-aware restore. Approval is required before
those runtime changes. No existing accepted ADR is edited/relabelled as accepted.

Changed files for this assessment: this gap analysis, STAGE-5-TEST-PLAN, proposed
ADR/index, scope/instructions, STATUS and CHANGELOG. APIs/OpenAPI, app/backend
code, dependencies, schemas and migrations are unchanged. No Stage 5 feature is
claimed implemented by documentation. Existing features pass the executed baseline.
Stage 5 remains incomplete pending architecture approval, implementation and full
acceptance. Next work is Stage 5 implementation after approval; not Stage 6,
hosting deployment or unrelated P1 voice implementation.


## Approved implementation update — 2026-10-16

The assessment/table above records the pre-change baseline. The maintainer has
now accepted ADR-041; architecture approval is no longer pending. Runtime
foundation changes and new migrations/tests are in progress; see
../STAGE-5-REPORT.md for the current implemented/pending distinction and actual
verification. Neutral labels, current-phone step-up, scoped role/admin/audit API,
expiry/epoch controls, recovery-word confirmation, pinned local context/private
state, device-wide retry ordering and scoped export sanitizer are implemented.
This does not complete all table requirements. Multi-household shipping UX/runtime,
caregiver copies, occupied-store import, complete sensitive UI/legacy routing,
assisted recovery, account/context deletion and recoverable manual event deletion
remain pending. Stage 6 and hosting are not authorized by this update.
