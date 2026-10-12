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

The optional cloud adapter defined by ADR-028 is separate, defaults off, and
requires its versioned disclosure and consent. There is no automatic transition
from native inference to cloud inference.

## Validation status

Native source compilation, method-channel behavior, fallback, strict merge, and
explicit-confirmation UI are automated. Actual inference latency, output quality,
language behavior, thermal/quota behavior, and offline operation remain physical
device release tests.
