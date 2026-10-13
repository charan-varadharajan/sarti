# Functional test scenarios

This catalogue is the maintained source of truth for Sarti functional scenarios.
It complements `TEST-STRATEGY.md`, which defines suites and quality gates.

## Scenario lifecycle

Every functional test follows the same lifecycle:

1. **Create:** allocate an isolated logical device and a fresh encrypted local
   database. Use synthetic data only.
2. **Seed:** load the named fixture through repositories, API clients, or
   protocol helpers. Do not create prerequisite data through UI unless creating
   that data is the behavior under test.
3. **Enter:** open the screen or flow under test with at most one navigation
   helper. Avoid replaying onboarding and unrelated screens.
4. **Exercise:** perform only the actions relevant to the scenario.
5. **Assert:** verify visible behavior and persisted/domain state. Security
   scenarios also verify forbidden state and disclosure are absent.
6. **Wind down:** close databases, dispose key material and controllers, clear
   provider stubs, and leave no state for another test.

The shared Flutter implementation is
`mobile/test/support/sarti_test_harness.dart`. It provides a fresh in-memory
SQLCipher database, a logical device ID, synthetic family fixtures, direct screen
entry helpers, reminder observations, and explicit teardown. It does not prove
Keychain/Keystore, passkey, native-model, push-provider, or physical-device
compatibility.

## Fixture catalogue

| Fixture | Starting state | Intended use |
| --- | --- | --- |
| `blankDevice` | Fresh encrypted database; no family | Onboarding and first-family creation only |
| `authorizedChildSyncPair` | Owner + explicitly authorized guardian, separate SQLCipher DBs/device keypairs, prepared family/calendar, controlled relay | Child profile synchronization and grant/security cases; `child_sync_fixture.dart` |
| `calendarReady` | Authorized logical device; Test family; Alex guardian; Mia and Jithu with private cloud aliases; empty calendar | Calendar, proposal, assignment, and reminder scenarios |

Fixtures must stay small and composable. Add a fixture only when multiple
scenarios need the same starting state. Scenario-specific records belong in that
scenario's setup helper.

## Mobile functional scenarios

| ID | Behavior | Fixture and target | Automation |
| --- | --- | --- | --- |
| `ONB-MOB-001` | A new parent can create a family and reach the calendar | `blankDevice` → onboarding | `mobile/test/foundation_screen_test.dart` |
| `CAL-MOB-001` | A parent adds a recurring event and assigns a child | `calendarReady` → add-event editor → saved-date agenda (widget handles midnight rollover) | Widget test plus `mobile/integration_test/calendar_add_event_scenario_test.dart` |
| `CAL-GRID-MOB-001` | Prepared day/week/month, proportional duration, navigation/agenda and tap-without-write | `calendarReady` + two events → grid directly; dispose DB/controllers | `mobile/test/calendar_grid_test.dart`, `mobile/integration_test/calendar_grid_scenario_test.dart` via shared support scenarios |
| `CAL-GRID-MOB-002` | Overlapping events remain separate; empty dates retain grid axes | Prepared overlapping events → day grid | Same widget/native suite |
| `CAL-GRID-MOB-003` | Narrow month and large text preserve accessible shared-child agenda in repository name order | Prepared shared event, 390×844 layout → month/agenda | Same widget/native suite; physical VoiceOver/TalkBack unverified |
| `CAL-GRID-UNIT-001/002/003` | Overnight carry-in/exact boundaries, canonical `Etc/UTC` timezone conversion and spring/fall DST duration/recurrence | Synthetic immutable domain events → presentation adapter; no UI setup | `mobile/test/calendar_occurrence_adapter_test.dart` |
| `CAL-GRID-SEC-001` | Other family/resource and tombstones/cancellations absent; display interactions cannot reschedule/resize | Synthetic scoped domain fixture → adapter | Same adapter suite; no new backend security boundary |
| `AI-MOB-001` | A natural-language proposal changes nothing until approval and supports Undo | `calendarReady` → proposal input | `mobile/test/natural_language_event_flow_test.dart` |
| `AI-MOB-002` | An ambiguous clock time requires the parent to choose AM or PM | `calendarReady` → proposal review | `mobile/test/natural_language_event_flow_test.dart` |
| `AI-MOB-003` | Unsupported or failed native AI uses the deterministic local parser | Parsed proposal → provider adapter | `mobile/test/native_ai_provider_test.dart` |
| `EMAIL-MOB-001` | A sealed, attributed email remains a proposal until approval | Prepared encrypted delivery → email inbox | `mobile/test/natural_language_event_flow_test.dart` |
| `SYNC-MOB-001` | Offline changes survive restart and duplicates do not duplicate events | Prepared device databases → sync engine | `mobile/test/calendar_and_sync_test.dart` |
| `SYNC-MOB-002` | Concurrent edits create an explicit conflict without silent loss | Diverged device databases → conflict resolver | `mobile/test/calendar_and_sync_test.dart` |
| `BACKUP-MOB-001` | Corrupt or incorrectly keyed backup data fails safely | Synthetic encrypted backup → restore service | `mobile/test/backup_service_test.dart` |
| `BACKUP-MOB-002` | Replacement installation restores with recovered SQLCipher key; BUG-002 | Prepared encrypted family + empty independent installation → stage/activate; tear down temp directories | `mobile/test/backup_recovery_test.dart`; real SQLCipher; protected-storage failure injection |
| `BACKUP-MOB-003` | Explicit phrase acknowledgement before upload | Direct prepared backup screen, synthetic phrase → upload; dispose widget | `mobile/test/backup_screen_test.dart` |
| `BACKUP-MOB-004` | Explicit phrase-validated restore | Direct screen with prepared downloaded backup → restore; dispose widget | `mobile/test/backup_screen_test.dart`; invalid input cannot invoke restore |
| `BACKUP-XPLAT-001` | iOS creates a real `.srtbk`; Android decrypts/restores the identical file; BUG-002 | Prepared synthetic recurring event/child/pickup/reminders → backup screen on iOS; host transfers ciphertext into Android app sandbox → restore screen; temporary databases and transferred files removed | `mobile/integration_test/backup_portability_test.dart`, `scripts/test_backup_ios_android.py`; native SQLCipher/libsodium on both OSs; passkeys/protected storage/production API excluded |
| `BACKUP-XPLAT-002` | Android creates a real `.srtbk`; iOS decrypts/restores the identical file; BUG-002 | Same prepared fixture and direct backup/restore screens as -001, reversed source/destination; native app sandbox transfer and teardown | `mobile/integration_test/backup_portability_test.dart`, `scripts/test_backup_ios_android.py --direction android-to-ios`; added but deliberately NOT RUN at user request |
| `BACKUP-API-001` | Full snapshot access respects owner, tenant, device and revision boundaries | Isolated PostgreSQL, synthetic passkey sessions/family → binary API | `backend/tests/integration/test_backup_api.py`; includes deletion purge |

| `CHILD-MOB-001` | Add child offline with explicit sharing intent | Prepared calendar → add-child dialog; dispose database/controller | `mobile/test/child_profile_sync_test.dart` |
| `CHILD-MOB-002` | Receiving calendar renders decrypted child label/colour | Prepared owner/guardian pair → receiving calendar | `mobile/test/child_profile_sync_test.dart` |
| `CHILD-NATIVE-001` | Native child creation, encrypted grant/profile delivery and receiving UI | Prepared two logical devices → add-child dialog, then receiving calendar; close databases/dispose keys | `mobile/integration_test/child_profile_sync_test.dart`; native SQLCipher/libsodium, controlled relay; physical authentication/network excluded |
| `CHILD-SYNC-001` | Offline creation, event-before-profile delivery, de-duplication | `authorizedChildSyncPair` → sync engines | `mobile/test/child_profile_sync_test.dart` |
| `CHILD-SYNC-002` | Lost receipt retries identical persisted envelope with recreated engine | Prepared outbox → failing relay → reconstructed engine | Same mobile test file |
| `CHILD-SYNC-003` | Legacy profile queues once without inventing sharing consent | Prepared legacy child + explicit fixture permission → provisioning | Same mobile test file |
| `CHILD-SYNC-004` | Concurrent rotation converges; revoked device receives no future key | Prepared authorized pair → advanced resource epochs | Same mobile test file; API serialization contract |
| `CHILD-SYNC-006` | Pending upload survives rotation, whether its receipt was lost or it never reached the server | Prepared profile/outbox → failed relay → new epoch → retry | Same mobile test file; exact-old-receipt versus new-stale-write API checks |
| `CHILD-SYNC-005` | New key replays profile skipped by earlier cursor | Prepared retained profile + advanced cursor → grant/import | Same mobile test file |
| `CHILD-SEC-001/002/003/004/005` | Grant signature/recipient/epoch, wrong device, revocation, tamper/scope, resource-kind separation, canonical wire vector | Prepared pair → key importer / authenticated decrypt / repository | Same mobile test file; no mocks for cryptography |
| `CHILD-UNIT-001` | Invalid local child input leaves no profile/outbox row | Prepared family → repository | Same mobile test file |
| `CHILD-MIG-001` | v5→v6 encrypted file retains profile, event assignment and pending writes; wrong key rejected | Temporary legacy encrypted fixture → open/migrate → delete | Same mobile test file |
| `CHILD-API-001` | Resource/key transport contains only authorized metadata and sealed keys | Loopback HTTP fixture → API client; close server | `mobile/test/child_sync_api_client_test.dart` |
| `CHILD-API-002` | Stable identity/consent, isolation, revocation, grant uniqueness and filtered pagination | Isolated PostgreSQL + prepared passkey boundary fixture → resource/grant/relay endpoints | `backend/tests/integration/test_child_sync_api.py`; real DB/authz/signature verifier, WebAuthn ceremony stub |

Backend authorization, tenant isolation, API abuse cases, migrations, email
routing, and relay retention remain catalogued as mandatory scenarios in
`TEST-STRATEGY.md`; add stable IDs here when their reusable server fixture
harness is introduced.

## Running a prepared scenario

From the repository root:

```sh
./test                     # all Flutter unit/widget tests; no device
./test --ios               # calendar + child + grid + guardian UI journeys; iOS simulator
./test --android           # same journeys; Android emulator
./test --ios --scenario calendar  # only CAL-MOB-001
./test --ios --scenario child     # only CHILD-NATIVE-001
./test --ios --scenario grid      # only CAL-GRID-MOB-001/002/003
./test --ios --scenario guardian  # only GUARD-MOB-001/002/003
```

The runner selects a running supported simulator/emulator automatically, or
starts an installed iPhone simulator / configured Android emulator if none is
running. Xcode with an iOS runtime or Android Studio with an AVD must already be
installed; tools must be on PATH. It never selects physical phones. With multiple
running devices, selection is sorted by ID; use `--device ID` to override.
It leaves the simulator/emulator open afterward; scenario fixtures handle their
own database/key teardown. First builds can take several minutes.

Watch UI actions in Simulator/Android Emulator. Terminal prints PASS/FAIL and
the full log path under ignored `test-results/`. The command returns nonzero
on setup/test failure and stops at the first failed scenario. Native mode uses
an explicit calendar/child/grid/guardian allowlist, not the whole integration directory: neither
backup portability direction is run. These commands do not run backend tests,
production-provider checks or the complete CI quality gates. BUG-012 remains
pending; this helper does not change CI.

Fast widget feedback:

```sh
cd mobile
flutter test test/foundation_screen_test.dart --plain-name CAL-MOB-001
```

Real Flutter engine on an Android emulator or iOS simulator:

```sh
cd mobile
flutter test integration_test/calendar_add_event_scenario_test.dart \
  -d <device-id> --plain-name CAL-MOB-001
```

The integration command creates and seeds its disposable database, enters the
calendar directly, performs the scenario, asserts the result, and closes the
database. It must never connect to production services.

## Maintenance rules

- Give each new functional journey a stable ID before or with its first test.
- Record its fixture, direct entry point, automation file, security assertions,
  and physical/provider limitations here.
- Reuse scenario IDs across widget, integration, and manual runs of the same
  behavior.
- A regression test references its `BUG-NNN` ID as well as the scenario ID.
- Update or remove stale catalogue rows in the same commit as the behavior.
- Do not put real family names, emails, tokens, keys, or production identifiers
  in fixtures, screenshots, logs, or golden files.

## Replacement-device security (BUG-010)

| Scenario | Prepared state and direct entry | Evidence |
| --- | --- | --- |
| `REPLACE-API-001` | Owner, restricted guardian, outsider and pending family membership → passkey completion | `backend/tests/integration/test_device_replacement.py`: accessible epochs, isolation, old sessions, replay, stale grants/writes, independent sealed-box and AEAD checks |
| `REPLACE-API-002` | Owner + family → injected session-creation interruption, retry same challenge | Same API suite: full transaction rollback and retry |
| `REPLACE-API-003` | One adult, two prepared passkeys → concurrent completions | Same API suite: serialized epochs, one active phone |
| `REPLACE-SEC-001` | Two keyed logical devices → revoke one and advance epoch | `mobile/test/device_replacement_test.dart`: real libsodium old-key decryption rejection, active-only grants, denied directory and absent future key after preparation |
| `REPLACE-SEC-002` | Missing initial key / already claimed advanced epoch → key preparation and local write | Same mobile suite: no invented key, write remains pending |
| `REPLACE-SYNC-001` | Prepared restored family and fresh admin identity, no historical keys → key preparation | Same mobile suite: unclaimed advanced epoch self-grant, encrypted future write, stable retries |
| `REPLACE-SYNC-002` | Same restored state → lose accepted self-grant response, retry | Same mobile suite: established key recovered without duplicate/replacement |

All fixtures are synthetic and disposable; prerequisites are seeded directly.
PostgreSQL API tests stub WebAuthn verification, not database transactions or
crypto libraries. Mobile tests use real SQLCipher/libsodium with a controlled
relay. They do not establish physical passkeys, protected storage, OS recovery
or production two-phone compatibility. No backup portability direction is run.

## Metadata ordering and compatibility (BUG-011)

| Scenario | Prepared direct entry | Evidence |
| --- | --- | --- |
| `AAD-UNIT-001` | Fixed metadata plus reversed top-level/vector order → encoder | `mobile/test/sync_metadata_test.dart`: exact known bytes, unchanged legacy encoding |
| `AAD-SEC-001` | Real libsodium ciphertext → mutate each metadata field/version | Same suite: authentication failure, unknown version and extra-field rejection |
| `AAD-SYNC-001` | Prepared SQLCipher v1 pending envelope → lost receipt and retry | Same suite: exact bytes/identity/version retained and legacy delivery accepted |
| `AAD-SEC-002` | Prepared old multi-author v1 ciphertext → reordered vector | Same suite: no application/cursor advancement, ciphertext preserved |
| `AAD-API-001` | Prepared owner/family → v1/v2 uploads and retries | `backend/tests/integration/test_sync_protocol.py`: version tag round-trip, mismatch/unknown rejection |
| `AAD-MIG-001` | Legacy fixture ciphertext → 0005/0006 upgrade/downgrade | Same backend suite: byte preservation and safe downgrade refusal with v2 rows |
| `AAD-HTTP-001` | Two prepared logical devices → real loopback HTTP/PostgreSQL/Dart encryption/sync | `mobile/test/postgres_sync_roundtrip_test.dart`, hosted by `backend/tests/integration/test_sync_postgres_mobile.py`: forced reverse vector order, real JSONB reorder, exact retry, conflicting alternatives, explicit resolution/event convergence |

The full Flutter suite skips only `AAD-HTTP-001` without its explicit host config.
Enable `SARTI_RUN_MOBILE_CONTRACT=1` and run the host test against an isolated
migrated PostgreSQL test DB. The host seeds credentials/membership, starts a
loopback API, generates ephemeral test config, invokes Flutter and tears down.
It never passes family keys to the backend. Logs are ignored under
`test-results/bug011-http-mobile.log`. These are synthetic local fixtures,
not real passkeys, protected storage or production networking. BUG-017 tracks
remote conflict-card retirement separately. Neither backup portability direction
is included.

## Guardian sharing and initial handoff (BUG-004)

| Scenario | Prepared fixture and direct target | Evidence |
| --- | --- | --- |
| `GUARD-MOB-001` | Owner family/child/event plus empty independent guardian → sharing screen → rendered token-only QR/share/copy → acceptance → owner code/permission review → decrypted read-only calendar | `guardian_screen_test.dart`, shared `support/guardian_scenarios.dart`, native `guardian_onboarding_scenario_test.dart` |
| `GUARD-MOB-002` | Empty guardian → malformed pasted invitation | Same widget/native suite: bounded error, no request |
| `GUARD-MOB-003` | Prepared owner invitation → failed share / expired QR | Same suite: copy fallback remains, expired QR removed |
| `GUARD-SEC-001/002` | Strict URI inputs / real encrypted family-profile adapter | `guardian_onboarding_test.dart`: foreign routes/query/invalid tokens rejected; wrong resource/malformed guardian leaves data unchanged |
| `GUARD-SYNC-001` | Prepared independent SQLCipher/libsodium devices, prior relay expired → approval and scoped handoff | Same unit suite: current events/durations/guardians survive; timestamped apply marker commits atomically, repeated refresh preserves one profile; unshared child remains nameless and has no key |
| `GUARD-SYNC-002` | Prepared pending guardian → lost approval response / retry / removal | Same suite: one handoff, stable operation IDs, no future key for revoked guardian |
| `GUARD-SYNC-003` | Approved handoff with old-identity outbox cleared → explicit retry | Same suite: orphaned progress cannot suppress a new scoped handoff |
| `GUARD-API-001` | PostgreSQL owner/guardian/outsider and prior ciphertext → accept/review/approve | `test_guardian_onboarding_api.py`: pending/cross-family/changed-device/permission/expiry/replay/cancel/quota abuse, exact approvals, baseline filtering, removed re-enrollment |
| `GUARD-MIG-001` | Existing metadata and nonzero approved baseline | Full migration suite + guardian API journey: upgrade defaults and safe downgrade refusal |
| `GUARD-HTTP-001` | Empty real Dart installations → loopback HTTP/PostgreSQL with stubbed WebAuthn → expired relay → actual signed sealed keys/current state | `guardian_postgres_roundtrip_test.dart`, explicit host `test_guardian_postgres_mobile.py`: real crypto/HTTP/profile isolation, idempotent handoff and revocation |

All prerequisites are seeded directly unless creation/acceptance/approval is the
behavior under test. Widget/native fixtures close databases, keys, controllers
and timers. Share/copy adapters capture only synthetic invitation text in tests;
they never send messages or replace a user's clipboard. QR rendering executes
in the widget/native engine. Scanning and OS routing/share apps require physical
validation; these tests do not establish them. No native passcode prompt is used.

`./test --ios --scenario guardian` and `./test --android --scenario guardian`
run the prepared native journeys; default native allowlists now include them.
The real HTTP host is opt-in (`SARTI_RUN_GUARDIAN_CONTRACT=1`) against an isolated
migrated PostgreSQL DB; ordinary full suites skip only its host-dependent Dart
case. Its synthetic-only expiration endpoint never exists in the shipping API.
Neither backup portability direction is selected. Physical passkeys/protected
storage, camera decoding, cold/warm links, clipboard/share delivery and production
networking remain independent release checks.
