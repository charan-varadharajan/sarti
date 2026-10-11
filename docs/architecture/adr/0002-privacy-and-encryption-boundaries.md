# ADR 0002: Privacy and encryption boundaries

- Status: Accepted
- Date: 2026-10-11

## Decision

Private family content is encrypted at rest on devices and end-to-end encrypted
between authorized devices. The persistent server application database may store
operational metadata and relay ciphertext, but not private family content in
plaintext. Use resource-scoped keys and established cryptographic libraries.

Incoming external email is plaintext before and during initial gateway
processing. Push payloads contain no sensitive family information. Revocation
prevents future access but cannot erase content previously downloaded.

## Consequences

Server search and cloud AI over private content are unavailable. Metadata must be
explicitly classified and minimized. Algorithm selection, envelope formats, key
hierarchy, recovery, and rotation require a reviewed follow-up ADR and threat
model before cryptographic implementation begins.
