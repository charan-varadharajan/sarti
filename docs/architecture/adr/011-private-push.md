# ADR-011: Privacy-preserving push notifications

- Status: Accepted
- Date: 2026-10-11

Provider-visible push payloads contain no sensitive family information. Use push
only for opaque wake-up or generic notification signals; fetch ciphertext and
render content on the authorized device. Provider selection remains unresolved.
