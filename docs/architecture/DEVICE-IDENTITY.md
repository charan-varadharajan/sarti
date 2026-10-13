# Device identity

Adults register and authenticate with WebAuthn passkeys using required user
verification and discoverable credentials. The backend uses `webauthn` 3.0.0,
five-minute one-use challenges, monotonic authenticator counters, hashed opaque
30-day session tokens, and deployment-configured RP ID/origin.

Completing a ceremony registers the device X25519 and Ed25519 public keys. Only
one phone may be active for an adult. A successful authentication from a new
phone atomically revokes the former device and its sessions. Every protected API
request binds the token to the adult and active device before family or resource
authorization runs. Biometrics only unlock local device secrets; they are not a
server credential.

The Flutter `passkeys` adapter and platform-secure key store are implemented.
Associated-domain/asset-link deployment and physical iOS/Android ceremonies have
not been verified because an RP domain and test devices are unavailable.

ADR-035/BUG-004 invitation review displays a comparison code derived with
SHA-256 from the recipient's registered signing/encryption public keys. The
owner confirms the same code on the intended guardian's phone, then pins the
full digest and active device UUID in approval. The displayed code is not a
resource key or passkey. Link/QR possession alone creates only pending status;
it cannot replace identity verification, resource approval or sealed grants.
