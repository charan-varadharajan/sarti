# P1 backlog

Updated: 2026-10-14.

The maintainer explicitly authorized moving into P1 with hosting/deployment
last, while retaining outstanding P0 release checks. P1 approval is not P0
acceptance, production readiness or approval of every previously deferred idea.

## P1-001 — Voice event proposals on iPhone and Android

Status: feature inclusion approved by maintainer on 2026-10-14; not implemented.
Priority: first approved P1 feature. No assistant compatibility has been demonstrated.

### User journey

Target experience: invoke the phone assistant, describe an event such as
“Mia has karate tomorrow at 4 PM”, then open Sarti's editable event proposal.
Unlock Sarti as required, review the child/date/time/duration/recurrence, and
explicitly confirm before the existing encrypted local save/sync/reminder flow.
The precise supported invocation phrases and parameter capture remain to be
verified; this example is a product goal, not a shipping command.

- iPhone: Siri and Shortcuts through Apple's App Intents/App Shortcuts capabilities.
- Android: target the configured Google mobile assistant, including Gemini where
  supported, using verified Android app-action/shortcut capabilities. “Hey Google”
  can invoke Gemini, but that does not prove arbitrary Sarti free-text invocation
  is supported. Assistant versions, device/account/language requirements, app
  publication eligibility and parameter delivery must be validated separately.
- If full-sentence handoff is unsupported, disclose the limitation. A shortcut
  that only opens Describe an event is a partial milestone, not full voice-entry
  acceptance. Keep manual/local description available without assistant support.

### Security and privacy requirements

- Assistant voice/transcription processing is a separate Apple/Google boundary;
  do not describe it as Sarti's verified on-device inference or promise locality,
  anonymity, no training, or zero retention. Match disclosures to verified versions.
- Sarti does not silently enable optional cloud assist. Once received, proposals
  use the approved native/local parser and existing explicit review path.
- Do not expose the household/profile directory, private events, resource keys,
  recovery phrases or reverse mappings to the system assistant for discovery.
- Incoming text/parameters are untrusted, bounded input. They cannot change
  authorization, select a different server, override instructions or auto-save.
- Require normal device/app unlock and current local resource permissions before
  showing protected context or saving; preserve paused recovery/read-only gates.
- No descriptions in URLs, logs, telemetry, push or persistent plaintext queues.
  Define secure native-to-Flutter transfer and interrupted-delivery behavior in
  architecture design before implementation; never persist plaintext just to
  support cold start. No autonomous background calendar writes.
- Missing/ambiguous date, time or child remains unresolved for user review.
  Preserve the visible one-hour duration default and existing DST semantics.
- Repeated assistant delivery cannot silently duplicate confirmed appointments.
  Confirmed changes use the existing encrypted outbox and conflict handling.

### Acceptance and verification

Prepared synthetic family/device fixtures and direct intent-to-proposal entry;
no UI setup except where setup itself is tested. Required planned scenarios are
listed in TEST-SCENARIOS.md as P1-VOICE-001 through P1-VOICE-012. Verify both warm
and cold start, cancellation, ambiguity, permissions, tampering/oversize, duplicate
activation and encrypted persistence. Physical Siri and Android assistant tests
are required for assistant claims; intent injection and mocks are insufficient.

The detailed [scope and test plan](../testing/P1-VOICE-TEST-PLAN.md) is mandatory:
unit, widget, Swift/Kotlin bridge, native E2E, API/OpenAPI contract, backend,
security/abuse, encrypted persistence/sync, migration, smoke and CI regression
coverage. Run complete automated gates for code changes, not just new cases;
report explicit exclusions and physical/provider limits. Register new tests in
CI and close Android-native/opt-in cross-layer automation gaps before claiming
full P1 automation. No backend endpoint or migration is invented solely for tests.

### Next work

Design the native-to-Flutter proposal handoff, review applicable ADRs and current
platform APIs/terms, and perform a compatibility spike on both platforms. Record
new architecture decisions without inventing accepted approvals; any accepted
ADR change follows the existing approval rule. Record exact OS/device/assistant/
language/account/build-distribution limits before promising invocation support.
No hosting, cloud billing, provider activation or store publishing is authorized
by adding this feature to the backlog.

### Official references reviewed 2026-10-14

- [Apple App Intents](https://developer.apple.com/documentation/appintents)
- [Android assistant app integration](https://developer.android.com/develop/devices/assistant/overview)
- [Build App Actions](https://developer.android.com/develop/devices/assistant/get-started)
- [Gemini mobile capabilities and Hey Google](https://support.google.com/gemini/answer/14579631)
- [Siri and Dictation privacy](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/)

## Stage 5 — scoped identity, membership, recovery and sensitive operations

2026-10-16: The maintainer supplied and authorized the Stage 5 product contract
(account registration, contextual roles, multi-admin/multi-household membership,
child/caregiver permissions, recovery, sensitive actions, audit and revocation).
This is now the active task. [Gap analysis](STAGE-5-GAP-ANALYSIS.md) records
existing reuse, actual baseline and conflicts. [ADR-041](../architecture/adr/041-stage5-scoped-membership-and-sensitive-operations.md)
was accepted by the maintainer on 2026-10-16; foundation implementation is
in progress. Full Stage 5 journeys and acceptance remain pending.
[Test traceability](../testing/STAGE-5-TEST-PLAN.md) covers all 17 mandated cases.
School/classroom authorization infrastructure is included; unrelated classroom/
social product functionality and Stage 6 are not implicitly authorized. P1-001
voice entry remains planned. Hosting stays last; no deployment/provider activation.

## Other candidates — not yet approved for implementation

External calendar synchronization, departure estimates, birthday invitations/
RSVP, pickup verification, activity groups, chores/rewards, groceries/meals and
document vault remain candidates from P0-SCOPE.md. Choose scope individually;
P1 authorization does not automatically select them.

## Deferred until last

Hosting/deployment remains last by maintainer instruction. Continue local/offline
engineering and prepared tests. P0 account/family deletion, physical-device and
provider acceptance gaps remain tracked; do not describe the app as release-ready.
