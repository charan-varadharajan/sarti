# Dependency governance

## Selection rules

Use the fewest established, maintained dependencies that satisfy an approved
need. Before adoption, review official release source, supported runtime,
maintenance, license, security advisories, native/platform behavior, transitive
dependencies, and privacy impact. Pin direct versions and commit resolver locks.

## Selections through Stage 3

Backend: FastAPI, Uvicorn, Pydantic Settings, SQLAlchemy, Psycopg, and Alembic;
development uses Pytest, HTTPX, Ruff, Mypy, Bandit, and pip-audit. Mobile uses
Flutter, Riverpod, `sqlite3` configured for SQLCipher, libsodium, platform secure
storage and local authentication, native passkeys, IANA timezone data, local
notifications, and SHA-256 support. The backend adds the maintained Python
`webauthn` verifier. Exact resolved versions live in the backend requirement
locks and `mobile/pubspec.lock`.

Stage 3 adds `firebase-admin`, `firebase_core`, and `firebase_messaging` for
opaque push wake-ups and
`google_generative_ai` for an optional locally pseudonymized cloud adapter. The
product owner explicitly approved this exception and reaffirmed it on
2026-10-11. Its disclosure and opt-in gate is implemented; production provider
data handling and credentials remain unverified.

Firebase's mobile SDK currently exposes registration tokens used by the accepted
ADR-026/backend contract. Firebase has announced a future move toward Firebase
Installation IDs for some token-management workflows. Treat that as an upgrade
watch item; do not change the wire contract without an approved ADR update and
provider/device regression testing.

The Android debug build currently warns that `firebase_core` still applies the
Kotlin Gradle plugin and must eventually support Flutter's built-in Kotlin
migration. The pinned version builds successfully today; recheck this warning on
every Firebase/Flutter upgrade before it becomes an enforced build error.

ADR-029 adds Android ML Kit GenAI Prompt API `1.0.0-beta4` and
`kotlinx-coroutines-android` `1.10.2`; iOS uses the OS-provided Foundation Models
framework. ML Kit Prompt API is beta, has no SLA, can introduce breaking changes,
and requires API 26. Its additional terms currently prohibit clients directed or
likely to be accessed by people under 18. The P0 client is an adult guardian UI;
a child-facing product cannot inherit this selection without renewed review.

`sqlite3` downloads checksum-pinned native artifacts via Dart build hooks. Sarti
selects its SQLCipher community build and verifies the engine at runtime. A
release process must additionally verify published artifact provenance/SBOMs.

ADR-031 adds `bip39_mnemonic` `4.1.0` for standard BIP-39 English recovery
phrase encoding and validation. The app supplies 128-bit entropy from the
existing libsodium random-byte API; it does not use the package's own random
generator. The direct dependency is MIT licensed and introduces `pointycastle`
and `unorm_dart` as resolver-locked transitive dependencies.

## Ongoing controls

### Calendar presentation selection

ADR-033 integrates maintainer-selected `kalender` 0.33.0 for BUG-016, pinned
exactly with its resolver lock. New transitive dependencies are linked_pageview
1.1.5 (Apache-2.0), scrollable_positioned_list 0.3.8 (BSD-3-Clause), and
universal_platform 1.1.0 (MIT); Kalender is MIT. SDK constraints, licenses and
source paths were reviewed; no calendar-content network/telemetry/persistence
path was found in the new UI packages. OSV reported no listed vulnerabilities
for those four exact versions on 2026-10-12. Preserve Sarti domain
recurrence/timezone rules and encrypted local storage/sync boundaries behind
the presentation adapter. Pre-1.0 minor upgrades may break APIs and must remain
explicit, reviewed changes. Execution evidence is in BUG-016-VERIFICATION.md.

CI checks dependency vulnerabilities. Updates are explicit reviewed changes with
tests; automated updates must not merge around failed checks. Material licensing,
security, privacy, or compatibility concerns trigger the contract stop condition.

### Guardian invitations (ADR-035)

Pinned direct packages: `share_plus` 13.3.1 (BSD-3-Clause), `app_links` 7.2.2
(Apache-2.0), `qr_flutter` 4.1.0 (BSD-3-Clause). SDK/build declared minimums meet
current Flutter 3.47.7, Dart 3.13.5, AGP 9.1 and Gradle 9.3.1. QR Flutter's older
stable release renders locally; no network or inference is introduced.

New lock entries: app_links_linux 1.0.4, app_links_platform_interface 2.0.4,
app_links_web 1.0.5 (Apache-2.0); cross_file 0.3.5+5, mime 2.1.0, qr 3.0.2,
share_plus_platform_interface 7.2.0, url_launcher_linux 3.2.3,
url_launcher_platform_interface 2.3.2, url_launcher_web 2.4.3 and
url_launcher_windows 3.1.6 (BSD-style notices retained). Exact licenses were
inspected in installed package sources; the lock stores checksums. OSV querybatch
returned no listed advisories for all 14 newly added exact versions on
2026-10-13. This is not an absence-of-defects guarantee.

Native targeted link/share source was checked for incoming-URL logging/network
telemetry: only a fixed debug-launch diagnostic was found in app_links; no token
logging path. Sharing invokes the user's OS chooser with token-only text and a
valid popover origin; no contacts or message/inbox access. QR uses an offline
painter. Desktop/web transitive adapters do not add those platforms to P0.
Physical sharing/camera/link behavior must be validated independently of mocks.

2026-10-14 / BUG-005: removed mobile `google_generative_ai` 0.4.7 and its lock
entry. No new package. Server broker uses existing pinned HTTPX with fixed host,
no redirects, bounded streaming and a total deadline. Provider deployment/model
eligibility must be verified separately before activation.
