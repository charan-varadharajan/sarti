# ADR-005: Passkeys, biometrics, and active-phone policy

- Status: Accepted
- Date: 2026-10-11

Use passkeys for adult authentication and device biometrics for local access.
Biometrics do not identify a device to the server. The backend permits one active
authorized phone per adult and revokes the former phone on replacement. Passkey,
attestation, recovery, and platform-storage libraries remain unresolved.
