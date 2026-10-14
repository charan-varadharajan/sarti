# AI architecture

## Event proposal path

1. The parent enters a sentence in the Flutter calendar.
2. The deterministic parser runs locally and produces a partial proposal.
3. The app asks the native platform bridge whether its on-device model is ready.
4. When ready, the native model receives the sentence and a fixed extraction
   instruction. No network or Sarti backend participates in this path.
5. Flutter parses the returned JSON as untrusted input. Native values may fill
   deterministic gaps but cannot replace locally resolved values.
6. The parent edits the proposal and supplies any missing date or time.
7. Only **Add to calendar** persists the event. The app then offers **Undo**.

Any unavailable capability, malformed output, quota error, or native exception
returns the deterministic proposal. The native path never invokes the optional
cloud Gemini adapter.

## Native adapters

| Platform | Adapter | Runtime gate |
| --- | --- | --- |
| iOS | Apple Foundation Models `SystemLanguageModel.default` | iOS 26+, model reports available |
| Android | ML Kit GenAI Prompt API `1.0.0-beta4` | API 26+, `FeatureStatus.AVAILABLE` |

Both adapters live behind the `app.sarti/native_ai` method channel. Errors sent
to Flutter use bounded codes and never include prompts or generated content.

## Privacy boundary

The input, prompt, and output stay inside the application process and platform
on-device model service for this flow. Sarti does not log them. The device's
normal OS diagnostics and vendor terms remain part of the platform trust
boundary. The app must use runtime capability checks because OS version alone
does not prove local model availability.

The optional cloud adapter defined by ADR-036 is separate, defaults off, and
requires its versioned disclosure and consent. There is no automatic transition
from native inference to cloud inference.

## Validation status

Native source compilation, method-channel behavior, fallback, strict merge, and
explicit-confirmation UI are automated. Actual inference latency, output quality,
language behavior, thermal/quota behavior, and offline operation remain physical
device release tests.

## Optional cloud adapter boundary

The adapter accepts local names only to replace references; it never exports
profile records or stored aliases. Fresh cryptographically random child,
guardian and place labels are scoped to one request, with reverse mappings in
memory only. No requester ID is added to the model payload. A conservative
English token grammar permits common activities/scheduling words and bounded
clock numbers. Unknown words/characters, ambiguous mappings and large input
block the request; there is no raw-text escape hatch. The model receives a
versioned JSON token array, not the entered sentence or arbitrary title/notes.

Only source-supported time/recurrence fields may enrich a proposal. Unexpected
fields, invented values, malformed/oversized responses and transport failures
return the local proposal. Dates, people, places and titles are not generated
by this cloud path. This limits its usefulness deliberately; unsupported input
uses the existing local/native proposal and explicit manual review.

Disclosure version 3 requires renewed opt-in for the ADR-037 server boundary. Scheduling tokens may still be
sensitive; common words can be identifiers and provider credentials/network
metadata permit correlation. No guarantee of anonymity, universal PII removal,
provider retention or no-training is made. See `../product/PRIVACY-MESSAGING.md`.

Tests capture the adapter's outgoing prompt with an injected transport and
verify zero calls for blocked requests. They do not establish a live Gemini
service/model, provider terms, retention or physical-device guarantees. The
implemented ADR-037 broker remains disabled; live activation/validation is
separately deferred by the maintainer. The direct mobile Gemini SDK was removed.

## ADR-037 broker / BUG-005

Native AI and deterministic parsing remain primary; Gemini is optional and
server-disabled by default. A user separately opts into disclosure v3 and taps
Use cloud assist on a review. Phone filtering produces fresh-label token JSON;
Sarti authenticates, validates and reserves atomic quota before an in-memory
fixed-host provider call. Both sides validate fields; phone checks source evidence.
No API event mutation occurs. Unsupported input/errors retain the local preview.
There is no direct mobile provider key or Gemini SDK; the old test adapter has
no default network transport. Live validation is deferred, per maintainer.
