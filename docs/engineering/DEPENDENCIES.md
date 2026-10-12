# Direct dependencies through Stage 3

Versions are pinned in manifests and full resolutions are committed. Selection
was verified against official package registries and resolved builds on
2026-10-11.

| Component | Version | Purpose |
| --- | --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 | iOS and Android app |
| flutter_riverpod | 3.4.3 | Composition |
| sqlite3 | 3.7.0 | SQLCipher FFI/build hook |
| sodium | 4.1.1+2 | X25519, Ed25519, XChaCha20-Poly1305, secure randomness |
| flutter_secure_storage | 11.2.0 | Keychain/Keystore secrets |
| local_auth | 3.0.2 | Device user-presence gate |
| passkeys | 2.23.1 | Native WebAuthn ceremonies |
| timezone | 0.11.1 | IANA timezone/DST recurrence |
| flutter_local_notifications | 22.3.1 | Device-local reminders |
| firebase_core | 4.15.0 | Firebase mobile initialization boundary |
| firebase_messaging | 16.7.0 | Opaque FCM token and wake-up transport |
| path_provider | 2.1.6 | Private database location |
| crypto | 3.0.7 | SHA-256 envelope digest |
| google_generative_ai | 0.4.7 | Approved optional Gemini assist behind local pseudonymization and explicit opt-in |
| Android ML Kit GenAI Prompt API | 1.0.0-beta4 | Gemini Nano on-device event-field extraction; runtime gated |
| kotlinx-coroutines-android | 1.10.2 | Android asynchronous native-model bridge |
| Apple Foundation Models | iOS 26 system framework | Apple on-device event-field extraction; runtime gated |
| FastAPI / Uvicorn | 0.143.0 / 0.54.0 | HTTP API/runtime |
| SQLAlchemy / Psycopg / Alembic | 2.1.3 / 3.3.6 / 1.20.0 | PostgreSQL/migrations |
| webauthn | 3.0.0 | Server WebAuthn validation |
| firebase-admin | 6.9.0 | Opaque FCM wake-up dispatch |
| PyNaCl | 1.6.2 | Maintained libsodium sealed-box binding for device-addressed email ciphertext |
| PostgreSQL | 17 | Server metadata/ciphertext relay |

License and dependency-review gates remain in CI. SQLCipher and cryptographic
libraries provide primitives; protocol tests and device validation are still
required for claims about end-to-end behavior.

The ML Kit Prompt API is beta and has no SLA or backward-compatibility promise.
Its pinned version, current terms, supported-device list, and physical-device
behavior must be reviewed on every upgrade and before a release.

Firebase mobile configuration, APNs credentials, and the backend service account
are deployment inputs rather than source dependencies. Provider token lifecycle
and Firebase's announced registration-token migration guidance must be reviewed
before each mobile release.
