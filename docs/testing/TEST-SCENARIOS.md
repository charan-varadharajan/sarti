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
| `CAL-MOB-001` | A parent adds a recurring event and assigns a child | `calendarReady` → add-event editor | Widget test plus `mobile/integration_test/calendar_add_event_scenario_test.dart` |
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
