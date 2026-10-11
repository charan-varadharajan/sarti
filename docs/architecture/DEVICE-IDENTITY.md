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
