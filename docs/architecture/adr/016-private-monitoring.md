# ADR-016: Privacy-preserving operational monitoring

- Status: Accepted
- Date: 2026-10-11

Collect only bounded operational signals needed to run Sarti. Exclude family
content, credentials, keys, raw ciphertext, email bodies, notification content,
and sensitive values from logs, traces, metrics, crash reports, and URLs.
Monitoring vendors and retention remain unresolved.
