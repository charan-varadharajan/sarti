# P1-001 — Scope, traceability and verification plan

Status: required plan, not implemented tests or compatibility evidence.
Approved feature scope: docs/product/P1-BACKLOG.md. Updated: 2026-10-14.

## Scope and boundaries

Implement iPhone Siri/Shortcuts and supported Android assistant invocation into
Sarti's existing editable event-creation proposal. Cover native activation,
parameter validation, safe native-to-Flutter handoff, warm/cold start, app unlock,
local/native interpretation, review/cancel/save, encrypted persistence, normal
sync and reminder scheduling after approval. Preserve current ambiguity,
one-hour default, recurrence, timezone/DST and child-selection behavior.

Voice entry creates proposals only. Autonomous writes, assistant calendar
search/read-out, voice deletion/editing, profile directory donation, new cloud
inference, permanent plaintext transcripts, new backend voice parsing, hosting,
store publication and other P1 candidates are outside this feature's scope.
A new endpoint is not required just because voice entry is added. Reuse normal
calendar sync; any justified endpoint change needs its own documented contract
and corresponding tests. Do not send raw descriptions to Sarti backend storage.

## Required traceability

Every requirement maps to stable scenarios, implementation modules, test files,
and executed results in the eventual implementation verification report. The
scenario catalog is TEST-SCENARIOS.md. Planned means no execution claim.

| Scenario | Test layers | Required assertions |
| --- | --- | --- |
| P1-VOICE-001 | Swift/Kotlin bridge, Flutter widget, native E2E, physical acceptance | Invocation supplies intended text/parameters; editable review; zero writes before explicit confirmation; correct child/date/time on save |
| P1-VOICE-002 | Unit, widget, lifecycle integration | Missing/ambiguous fields stay unresolved; cancel and interrupted cold/warm launch do not write; background/resume and repeated launches preserve safe state |
| P1-VOICE-003 | Widget, native integration, existing API/security regression | Locked app, read-only/revoked device, changed account/family, paused recovery and stale access cannot bypass permissions; another adult's private state stays inaccessible |
| P1-VOICE-004 | Native input contract, unit, security, captured transport/logs | Malformed types, Unicode/boundaries, oversized fields, forged origins and prompt injection cannot change app instructions/server/permissions; no content in URLs/logs/telemetry/push/plaintext queues; no silent cloud call |
| P1-VOICE-005 | Unit, repository/SQLCipher, sync integration | Repeated delivery/confirmation does not duplicate confirmed writes; exact elapsed duration, recurrence and DST semantics; conflict alternatives survive |
| P1-VOICE-006 | Physical iPhone and Android acceptance | Actual Siri/Shortcuts and configured Android assistant invocation; record OS/device/assistant/language/account/distribution requirements; unsupported devices have truthful fallback |
| P1-VOICE-007 | Backend unit, PostgreSQL API integration, HTTP/Dart contract | Approved local write uses existing encrypted sync API; authentication, active-device/resource/family isolation, replay/idempotency, expiry and structured errors remain correct |
| P1-VOICE-008 | Native/Flutter contract, API/OpenAPI contract | Versioned bounded handoff shape, wrong/missing/unknown fields and unsupported versions fail safely; existing public OpenAPI remains unchanged or is regenerated with justified endpoint changes |
| P1-VOICE-009 | Encryption/security, database integration, migration when applicable | Persisted events/outbox remain encrypted; server receives ciphertext without description/names; wrong keys/tamper fail; existing encrypted records survive any changed local/server migration |
| P1-VOICE-010 | Unit/widget, native integration, physical acceptance | No reminder before save; approval invokes existing local reminder flow once; notification/push content stays privacy-preserving; real OS delivery reported separately |
| P1-VOICE-011 | Regression, CI/build smoke | Existing calendar, family/child/adult/pet, retention, recovery, conflicts, sync, backup, email and AI consent behavior stays green; both shipping-platform builds compile |
| P1-VOICE-012 | Repository/CI security and dependencies | Static checks, secret scan, approved dependency/license review and vulnerability checks; no credentials or private fixture content in artifacts |

## Fixture and isolation contract

Seed synthetic families A/B, independent devices/keys, parent/guardian/private
resource permissions, children/colors, existing events and paused recovery states
outside the UI. Enter directly at the native handoff or proposal screen; create
prerequisites via UI only if that setup is the tested behavior. Use real SQLCipher
and libsodium for encryption claims and isolated PostgreSQL for backend tests.
Use controlled local relay/provider adapters; never real family data or live
assistant/cloud/provider calls in ordinary CI. Dispose databases, pending input,
app state and temporary files between tests. Artifacts must contain synthetic
or sanitized diagnostic data only; no credentials, keys, transcripts or dumps.

## Full automated regression requirement for code changes

For each feature/fix/refactor/API/schema/dependency/CI-runner code change, add
meaningful targeted tests, run them during development, then run the full existing
applicable automated suites plus new tests on the final source before completion.
The full gate is broader than ./test, which only runs Flutter unit/widgets by
default. Passing only a selected new test cannot establish full regression status.

| Gate | Required execution |
| --- | --- |
| Flutter | Entire unit/widget/security suite with coverage; format and analyze; all newly added cases discovered by default |
| Backend/API | Entire Pytest suite with coverage against isolated PostgreSQL, including integration, tenant/device/resource/security and existing enabled HTTP/Dart cross-layer contracts; no integration deselection for a full-suite claim |
| Native UI/integration | All registered prepared native journeys on both iOS simulator and Android emulator, including new voice handoff cases; explicit exclusions below remain |
| Platform builds | Normal Android build and unsigned normal iOS build; platform bridge/unit checks added for changed Swift/Kotlin code |
| Contracts and migrations | Generated OpenAPI drift; local/server migration regression suites; add preservation/negative tests whenever schemas or formats change |
| Security/dependencies | Ruff, Mypy, Bandit, pinned secret scan, dependency advisory checks, and governance/license review for new dependencies; preserve encryption/privacy/permission invariants |
| Smoke/tooling | Local Docker startup/health smoke, version integrity and repository test-runner/CI tooling tests |

New per-layer tests are required where behavior at that layer changes. If voice
entry needs no backend/API/schema change, do not invent an endpoint or migration
just to add a test: run the existing full backend/API/migration regression gates
and document why feature-specific implementation at that layer is unnecessary.
A missing service/runtime is a reported blocked/not-run gate, never a pass.

## CI automation deliverables and current gaps

Main pushes and PRs already trigger CI. Register new unit/widget/backend/security
cases in default suites; register native voice cases in the allowlisted native
runner. Before claiming full P1 automation, ensure CI executes both native
platform suites and the enabled HTTP/Dart cross-layer contracts with prerequisites,
fails on errors/timeouts/missing expected results, and publishes per-suite counts,
failed names and sanitized artifacts. A local pass is not a remote CI pass.

Current ci.yml has backend/PostgreSQL tests, Flutter unit/widgets, Android build,
iOS native journeys and quality gates. It does not yet run Android emulator
journeys or enable both HTTP/Dart opt-in contract hosts. Closing those automation
gaps is part of P1-VOICE-011 acceptance, not work already delivered by this plan.
Do not hide missing coverage with unconditional skips or weaken assertions.

## Explicit execution exclusions and reporting

- Hosted deployment remains last. Local Docker/PostgreSQL automation does not
  require deploying production or enabling cloud billing.
- Live Gemini testing remains deferred under BUG-005. Synthetic mocks establish
  local behavior, not provider terms/retention or assistant compatibility.
- Android-to-iPhone backup portability remains explicitly not authorized to run;
  full regression does not override that request. Report the exclusion.
- Real Siri/Android assistant, passkeys/protected storage, OS notification delivery
  and live email/push need separately recorded physical/provider acceptance.
- Documentation-only changes run documentation consistency, version/whitespace
  and secret checks; do not present old application results as a fresh full run.

Report exact commands/source revision, suite counts, pass/fail/skips and reasons,
failed test names, unexecuted gates and physical/provider limits. Keep full logs
in ignored artifacts; inspect failed cases only, following the maintainer's
failure-investigation authorization. After authorized spot fixes, rerun failed
cases and the full affected gates on the final source. Never close acceptance
with unexplained failures or call planned tests implemented/executed.
