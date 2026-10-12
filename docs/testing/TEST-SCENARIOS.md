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
| `BACKUP-API-001` | Full snapshot access respects owner, tenant, device and revision boundaries | Isolated PostgreSQL, synthetic passkey sessions/family → binary API | `backend/tests/integration/test_backup_api.py`; includes deletion purge |

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
