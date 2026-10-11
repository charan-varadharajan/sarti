# Device identity

## Approved invariants

- Adults authenticate with passkeys.
- Device biometrics gate local access and do not authenticate to the server.
- The backend allows one active authorized phone per adult.
- Replacing a phone blocks the former phone from future server access.
- Revocation cannot erase content already downloaded.

## Required server checks

Protected requests will bind the authenticated adult to a registered active
device, then authorize family role and resource scope. Device IDs are opaque and
unguessability is never used as authorization.

## Unresolved before implementation

Passkey server library and ceremony details, device key attestation, replacement
confirmation, recovery, biometric policy, platform secure-storage APIs, and
session/token formats require an approved design and abuse-case tests.
