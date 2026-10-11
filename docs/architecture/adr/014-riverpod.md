# ADR-014: Riverpod state management

- Status: Accepted
- Date: 2026-10-11

Use Riverpod for Flutter state management and dependency injection. Providers
must expose application interfaces rather than allow UI code to reach storage,
cryptography, transport, or native APIs directly.
