# ADR-029: Native on-device AI bridges

- Status: Accepted
- Date: 2026-10-11

## Context

ADR-009 requires verified native on-device AI with a deterministic fallback.
ADR-023 initially stopped at a provider interface because no suitable Flutter
package was selected. Both supported platforms now expose first-party native
APIs that can be called through a small Flutter method-channel adapter.

## Decision

- iOS uses Apple's Foundation Models framework and
  `SystemLanguageModel.default`. It is attempted only on iOS 26 or later after
  the framework reports the model as available.
- Android uses ML Kit GenAI Prompt API `1.0.0-beta4` and the stable/default
  on-device model selected by `Generation.getClient()`. The application minimum
  Android API level is 26, as required by this SDK.
- Flutter calls both implementations through the private
  `app.sarti/native_ai` method channel and checks availability before inference.
- The deterministic parser always runs first. Native output may fill only
  unresolved fields; it cannot replace a value already extracted locally.
- Native output is untrusted JSON. Invalid, unavailable, downloading, disabled,
  or failed model responses fall back to the deterministic proposal.
- No cloud fallback is invoked by this path. The separately approved optional
  cloud adapter remains subject to its own disclosure and consent gate.
- Every proposal is shown in an editable review UI. Calendar state changes only
  after the parent taps **Add to calendar**, and the resulting write offers
  **Undo**.

## Consequences

Apple Intelligence availability depends on OS, hardware, language/region,
settings, and model readiness. Android Prompt API support depends on AICore,
the installed Gemini Nano model, and Google's current supported-device list.
Unsupported devices retain the deterministic parser.

The Android API is beta and carries no SLA or backward-compatibility guarantee.
Dependency updates therefore require an explicit build, behavior, privacy, and
device-matrix review. ML Kit GenAI terms currently restrict clients directed or
likely to be accessed by people under 18; Sarti's P0 UI is for adult guardians.
Any child-facing client requires a new provider and legal review.

Compilation and mocked availability/failure tests establish integration
behavior. Successful private on-device inference must be demonstrated on
eligible physical iOS and Android devices before release.
