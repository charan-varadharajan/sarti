# ADR 0004: On-device AI and explicit approval

- Status: Accepted
- Date: 2026-10-11

## Decision

Private family information is processed only through verified native on-device AI
APIs. There is no cloud inference or silent cloud fallback. A deterministic local
implementation handles unsupported devices and failures. AI output is untrusted,
schema validated, presented as a suggestion, and applied only after explicit user
confirmation.

## Consequences

Capability detection must fail closed. Provider APIs require verification against
official SDKs and supported hardware. Tests must cover malformed output, prompt
injection, unavailable models, cancellation, and confirmation boundaries.
