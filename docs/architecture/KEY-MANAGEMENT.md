# Key management

Resource-scoped E2EE and user-owned recovery are approved. A key protocol is not.
Stage 1 only verifies that the chosen SQLite binding actually loads SQLCipher; it
does not create, store, derive, wrap, exchange, rotate, or recover production
keys and therefore does not claim E2EE.

Before implementation, approve established algorithms and libraries plus device
identity keys, resource key granularity, authenticated envelope metadata, nonce
rules, key distribution, membership changes, device replacement, rotation,
backup derivation, recovery, destruction, and protocol versioning. The server
must never receive material capable of decrypting family content.
