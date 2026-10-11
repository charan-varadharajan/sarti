# ADR 0001: Mobile and backend system baseline

- Status: Accepted
- Date: 2026-10-11

## Context

Sarti needs native mobile access, offline operation, a narrow coordination server,
and a codebase that can be reviewed as a coherent system.

## Decision

Use Flutter and Dart for iOS and Android, Riverpod for app state, and SQLite with
SQLCipher for local persistence. Use a Python FastAPI modular monolith backed by
PostgreSQL for server-side operational data. Use Docker for local development.
Production hosting remains undecided.

## Consequences

Mobile and backend boundaries require explicit versioned contracts. Native
platform integrations need real-device verification. A modular monolith avoids
premature distributed infrastructure while still requiring module isolation.
