# ADR-010: Inbound email plaintext boundary

- Status: Accepted; provider unresolved
- Date: 2026-10-11

Ordinary inbound email is plaintext before and during initial gateway processing.
Document this exception, minimize exposure and retention, isolate parsing, and
treat content as hostile. Provider, attachment policy, retention, and the exact
transition to encrypted suggestions require approval before implementation.
