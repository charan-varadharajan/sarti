# ADR-009: On-device AI and deterministic fallback

- Status: Accepted
- Date: 2026-10-11

Process private family information only with verified native on-device AI APIs.
Use a deterministic local fallback when the capability is unavailable or fails.
Never use cloud inference or a silent cloud fallback. Treat output as untrusted
and require explicit approval before saving a proposed change.

ADR-029 records the implemented Apple Foundation Models and Android ML Kit
bridges, runtime gates, strict merge behavior, and physical-device release gap.
