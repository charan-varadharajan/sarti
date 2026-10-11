# ADR-023: Natural-language event parsing

- Status: Accepted
- Date: 2026-10-12

## Decision

Natural-language input is parsed into a structured `EventProposal` through a
two-layer pipeline. The deterministic parser runs first and always. An optional
cloud AI layer may assist when explicitly configured, subject to the input
sanitization boundary below.

## Deterministic parser (mandatory, always runs)

A pure-Dart rule-based parser extracts title, date, time, recurrence, location,
child first-name tokens, and guardian first-name tokens from raw user text using
regex and keyword matching. It returns explicit uncertainty fields rather than
fabricating missing values. It has no dependencies beyond the Dart SDK and
timezone data already in the project.

## Cloud AI assist (optional, additive only)

`google_generative_ai` may be used to improve structured extraction from
ambiguous input. The following rules are binding and may not be relaxed without
a superseding ADR:

1. **Raw text only.** The prompt sent to the cloud model is the verbatim user
   input string and a fixed system instruction. No family IDs, resource IDs,
   adult IDs, child profile data, guardian names linked to accounts, session
   tokens, device identifiers, or any data from the encrypted local database are
   ever included in the prompt or any request metadata.
2. **No context injection.** Resolving a first-name token ("Mia") to a local
   child profile happens entirely on-device after the cloud response is received.
   The cloud model never learns that "Mia" is a profile in any family.
3. **Additive only.** The cloud response may only fill fields the deterministic
   parser left uncertain. It may not override a field the deterministic parser
   already resolved with high confidence.
4. **No API key, no cloud call.** If `SARTI_GEMINI_API_KEY` is absent the cloud
   layer is skipped entirely and the deterministic result is used.
5. **Structured output only.** The model is instructed to return a JSON object
   with fixed fields. Free-form model output is rejected.

## Proposal and confirmation

The parser output is always presented as a visible proposal distinct from saved
calendar state. No event is created or modified without explicit user
confirmation. The proposal is editable before confirmation. Easy undo is
available after confirmation by deleting or editing the created event.

## Uncertainty handling

Fields the parser cannot resolve with confidence are left null and shown as
empty in the proposal UI. The user fills them in before confirming. Missing
dates, times, locations, or participants are never fabricated.

## AiProvider interface

An `AiProvider` interface is the seam between the parser and any AI backend.
The deterministic parser implements this interface as the default. The cloud
assist implements it as an optional override. Future on-device LLM packages
(Apple NaturalLanguage, Gemini Nano) may implement the same interface under a
new ADR when stable verified Flutter bindings exist.

## Dependency

`google_generative_ai: 0.4.7` is added as a pinned dependency. It is used only
in the `GeminiAiProvider` adapter behind the `AiProvider` interface. It is never
imported from domain or application code directly.
