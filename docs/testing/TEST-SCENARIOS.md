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

## Optional cloud privacy — ADR-036 / BUG-005

| Scenario | Prepared fixture / direct entry | Required assertion |
| --- | --- | --- |
| `CLOUD-PRIV-001/002` | Synthetic child/place names → protector, no UI setup | Fresh labels per invocation; same label within invocation; exact local reverse mapping; Unicode/boundary/ambiguity checks |
| `CLOUD-PRIV-003` | Prepared local proposal → actual adapter with captured transport | Only bounded structured tokens, no raw sentence/stored alias/requester/account/device/profile metadata; additive grounded result |
| `CLOUD-PRIV-004` | Synthetic private/injection/unsupported inputs → adapter | Zero transport calls; identical local fallback |
| `CLOUD-PRIV-005/006` | Prepared proposal + synthetic provider responses → adapter | Strict schema/evidence, no invented time/recurrence/names/addresses; local failure fallback |
| `CLOUD-CONSENT-002` | SQLCipher v1-enabled preference → v2 store | Fresh opt-in required; reversible choice |
| `CLOUD-CONSENT-MOB-001` | Prepared family/calendar and consent off → Privacy & AI screen | Qualified disclosure, fresh-label/network caveats, explicit reversible opt-in; no provider call or event write |

Implemented in `cloud_prompt_privacy_test.dart` and `cloud_ai_consent_test.dart`.
Fixtures close independent databases; transport capture never contacts Gemini.
No native plugin changes or live provider/device claims are inferred.

## First-family permission refresh — BUG-019

| Scenario | Prepared fixture / target | Assertion |
| --- | --- | --- |
| `BOOT-PERM-001` | Empty SQLCipher household, prepared device keys/offline bootstrap → Create family | Event and Add child controls appear immediately without restart; opening/cancelling event editor writes no event |
| `BOOT-PERM-002` | Prepared existing owner family → offline bootstrap | Owner retains creation controls |
| `BOOT-PERM-003` | Prepared family with encrypted read-only guardian or revoked access cache → bootstrap/range change | Neither role gains event/child mutation controls on rebuild |

Implemented in `mobile/test/bootstrap_permission_refresh_test.dart`. Family
creation is deliberately exercised through UI only in -001 because it is the
transition under test. Other prerequisites are seeded directly. Widgets unmount
before database/key teardown. Secret storage/reminders are injected; real
SQLCipher/libsodium execute, but physical passkeys/storage/network are not proven.

## Today navigation — BUG-018

| Scenario | Prepared fixture / direct entry | Required assertions |
| --- | --- | --- |
| `CAL-TODAY-MOB-001` | Prepared yesterday/today/tomorrow events and fixed clock → 390×844 calendar | Repeated selected Today taps return from past/future; selection stays valid; records/outbox unchanged |
| `CAL-TODAY-MOB-002` | Same prepared calendar → Week/Month, navigate away, agenda → Today | Current date/day layout; agenda retained; only today's events; no writes |
| `CAL-TODAY-MOB-003` | Prepared calendar → Week/Month, navigate away → Go to today icon | Current period restored without changing layout or outbox |
| `CAL-TODAY-TZ-001` | Fixed UTC instants with UTC-ahead/behind and Vancouver spring/fall DST display zones → calendar | Today uses configured IANA-zone date rather than host/UTC date; visible range covers that instant; no writes |

`calendar_today_test.dart` registers shared `support/calendar_today_scenarios.dart`.
The existing native `calendar_grid_scenario_test.dart` includes these seven
cases alongside the three grid scenarios: `./test --ios --scenario grid` or
Android counterpart. Fixtures inject a clock and seed prerequisites without UI;
widgets/controllers/databases are torn down. No native clock, passkey, provider,
backup or physical-phone compatibility is inferred from controlled fixtures.

## Optional family setup — BUG-020

| Scenario | Prepared fixture / target | Assertion |
| --- | --- | --- |
| `ONB-MOB-001` / `BOOT-PERM-001` | Empty logical device → Create family → Skip setup | Calendar and owner creation controls, no mandatory details/children |
| `FAMILY-MOB-001` | Empty SQLCipher fixture → setup name drafts → Back | No family/outbox write before explicit Continue |
| `FAMILY-MOB-002` | Same fixture → named family → two child additions with custom/default colours → calendar | Names/colours retained; distinct defaults; sharing off; one family/two child operations; no event write |
| `FAMILY-MOB-003` | Empty fixture → defaults → one explicit child save → Back | Saved family/child survive leaving optional setup |
| `FAMILY-MOB-004` | Prepared created family → child form with invalid alias | Retained draft/error; no child/outbox writes; cancellation and empty calendar allowed |
| `FAMILY-MOB-005` | Prepared family with six used palette colours → child form | No implicit duplicate default; explicit reuse required |
| `FAMILY-SEC-001` | Prepared owner child form → cached access revoked while open | Save disabled; no child write |
| `FAMILY-SYNC-001` | Prepared owner/guardian SQLCipher + libsodium devices → shared editor custom colour → controlled encrypted relay | Authorized receiver preserves selected colour/name; ciphertext operations |

`family_setup_test.dart` registers shared `support/family_setup_scenarios.dart`.
The seven new scenarios also run in the existing native calendar entry point:
`./test --ios --scenario calendar` / Android counterpart (plus its existing event
journey). Fixtures seed prerequisites directly except creation actions themselves
under test. Widgets/controllers/database/key material are torn down. The existing
child native suite separately checks shared-editor compatibility with encrypted
profile delivery. Passkeys, platform secret stores and real transport are not
established by the controlled relay. Results: BUG-020-VERIFICATION.md.

## Adult/pet journeys — accepted ADR-038

Maintainer requested adult-private appointments, deliberate household sharing,
pet appointments and selectable pastel colours on 2026-10-13. These scenarios are implemented; executed results and platform limits are in
`ADR-038-VERIFICATION.md`. ADR-038 is accepted by explicit maintainer approval.
Prepare independent adult devices/resources directly; enter the target calendar
or editor without UI onboarding. Tear down databases, keys and synthetic relay state.

| Stable ID | Target / required assertion |
| --- | --- |
| ADULT-PRIVATE-001 | Adult editor: private offline save/reconnect; spouse and owner cannot read |
| ADULT-SHARE-001 | Explicit household preview/share and spouse pickup; only shared copy delivered |
| ADULT-SEC-001 | Resource/grant/relay/restore deny other adults and cross-family requests |
| ADULT-CONFLICT-001 | Shared edits, retries and unsharing preserve genuine conflicts |
| ADULT-RECOVERY-001 | Family backup excludes others' private content; separate adult recovery validated |
| PROFILE-COLOUR-001 | Pastel choices persist/sync; legacy colours preserved; labels/contrast usable |
| PET-CAL-001 | Prepared pet: create/edit/sync household appointment |

Additional stable coverage: `ADULT-UI-001` enters a prepared calendar directly,
saves through the private editor and verifies sharing defaults off;
`ADULT-DRAFT-001` binds unpublished local drafts once and rejects inheritance by
a later account; `ADULT-RECOVERY-002` stages/activates the real encrypted snapshot,
rejects the wrong adult and preserves a newer unsynced edit against old relay data;
`ADULT-API-001` checks metadata-only provisioning and personal binary routes;
`ADULT-HTTP-001` extends the existing real PostgreSQL/HTTP/Dart host with private
crypto, owner exclusion and an explicit distinct household copy. The combined
host uses prepared authenticated synthetic principals, not real passkeys.

`./test --ios --scenario adult` / `./test --android --scenario adult` select the
ten prepared adult/pet/native SQLCipher/libsodium/recovery scenarios. `all`
includes them. These are same-platform recovery checks, not either cross-platform
backup portability direction; Android-to-iOS remains deliberately unrun.

`PROFILE-CHILD-001`: seed a legacy-colour child and current guardian grants,
enter People & pets directly, deliberately choose a pastel and verify the
same ID/name/new colour at the encrypted receiving device. Initial synchronization
retains the legacy colour until the explicit edit. This closes BUG-015's existing
profile correction coverage rather than inferring it from creation tests.

## Family-managed mobile calendar retention — accepted ADR-039

Implemented prepared fixtures with fixed clocks, independent SQLCipher stores,
synthetic principals/relay and direct retention-screen entry. Teardown closes
stores/keys, UI/controllers, temporary migration files and synthetic HTTP state.
No prerequisite creation is performed through UI. Results: ADR-039-VERIFICATION.md.

| Stable ID | Coverage |
| --- | --- |
| RETENTION-UI-001 | Family scope, admin-only controls, preview/confirmation, exact five choices/default |
| RETENTION-MOB-001 | Expired event removed, future event preserved, reminder cancelled; no deletion before confirmation |
| RETENTION-TIME-001 | End/exact cutoff, ongoing/future, Never, month-end/leap-year and spring DST |
| RETENTION-SERIES-001 | Active/unbounded and future finite series preserved; completed count expires; evaluator cap retains data |
| RETENTION-REMOVED-001 | Expired manual tombstones lose event details while keeping replay protection |
| RETENTION-SYNC-001/002 | Minimal records, actual content removal, duplicate/stale replay, concurrent edit/deletion and explicit review |
| RETENTION-CONFLICT-001 | Pending edits deferred; genuine deletion conflict preserved; Keep prevents repeated cleanup of that version |
| RETENTION-SEC-001 | Shared cleanup requires admin, own-private cleanup stays scoped, cross-family input rejected |
| RETENTION-MIG-001 | Real encrypted v7→v8 file upgrade retains event/pending retry bytes; wrong key fails |
| RETENTION-CRYPTO-001 | Independent devices, SQLCipher/libsodium, offline cleanup→encrypted relay→receiver removal; duplicate convergence |
| RETENTION-KEEP-RECOVERY-001 | Personal backup/staging retains the reviewed Keep vector; shared Keep survives initial guardian handoff |
| RETENTION-RESTORE-001 | Unvalidated family recovery marker blocks automatic sweep |
| RETENTION-API-001 | Real PostgreSQL/API: five periods, owner/delegated-admin, writer/outsider/revoked denial, revision conflicts, malformed input |
| RETENTION-MIG-002 | Real PostgreSQL 0009 upgrade/downgrade guard; legacy inactive default and exact ciphertext preservation |

`./test --ios --scenario retention` / Android counterpart register twelve
prepared scenarios (ten shared plus migration/encrypted convergence). `all`
includes retention; no backup portability direction is implicitly added. Neither
physical OS/background scheduling nor BUG-022 recovery continuation is established
by these fixtures. Broader timezone/DST/recurrence rules retain existing suite
coverage; real providers and disconnected-phone timing need physical validation.

## Family recovery continuation — accepted ADR-040 / BUG-022

Prepared independent encrypted source/replacement stores, actual v2 snapshot
staging/activation, libsodium relay and direct recovery-screen entry. No UI
prerequisites. Teardown closes stores and clears temporary files/key buffers.
These are default regression tests; historical expected-red evidence remains in
BUG-022-DESIGN-REVIEW.md. Current execution: BUG-022-VERIFICATION.md.

| Stable ID | Assertion |
| --- | --- |
| RECOVERY-CONT-001 | Historical epoch decrypts; stale update cannot overwrite |
| RECOVERY-CONT-002/002A | Concurrent edit retained; explicit merged-vector resolution |
| RECOVERY-CONT-003/003A | Unsent edit/create/delete reviewed under fresh operation/device/epoch; exact lost-receipt retry, stable event IDs |
| RECOVERY-CONT-004 | Current owner/resource authority overrides saved history |
| RECOVERY-CONT-005/005A/005B | Incomplete legacy block, corrupt ciphertext/cursor protection, interrupted queued-intent re-export |
| RECOVERY-CONT-006/006A | Prepared review card, cancel/resume cleanup, stale policy approval rejection |
| RECOVERY-CONT-007 | Missing child provisioned only with new explicit sharing choice; old consent not reused |
| RECOVERY-GATE-001 | Unreviewed outgoing mutation denied before upload |
| RECOVERY-SCOPE-001 | Cross-family snapshot catalog rejected before activation |
| RECOVERY-KEY-001/002 | Recovery excludes private keys and implicit publication; established epoch requires verified self grant |
| RECOVERY-RETENTION-001 | Expired content removal includes completed recovery intent; unreviewed intent stays protected |
| RECOVERY-MIG tests | Actual encrypted v8→v9 preservation, legacy block, wrong-key rejection |
| RECOVERY-HTTP-001 (within GUARD-HTTP-001) | Real HTTP/PostgreSQL replacement, encrypted snapshot/grants, reviewed current-epoch upload, revoked former session |

Run `./test --ios --scenario recovery` or `./test --android --scenario recovery`.
Native same-platform tests exercise real encryption and the prepared UI with
synthetic relay/authority; the separate HTTP host exercises server integration.
WebAuthn, protected-secret storage, push and physical lifecycle are not claimed
from these fixtures. Android→iOS backup portability remains explicitly not run.

## Combined remaining bugs — 2026-10-14

Prepared fixture/direct target entry; source stores use SQLCipher, sync fixtures
use real libsodium but synthetic relay/authority, and cloud UI uses an explicit
capturable synthetic broker. Teardown unmounts UI, closes stores, clears temp files.
Native shortcut: `./test --ios --scenario regressions` or Android equivalent.
The CI runner executes only the eight allowlisted native scenario entrypoints;
BACKUP-XPLAT-002 and all portability transfers stay excluded.

| Stable scenario | Coverage |
| --- | --- |
| NLP-BATCH-001 | Separate times/children with explicit shared context; shared-child single event |
| NLP-DURATION-001 | Noon/midnight, durations/end range, invalid/conflicting timing |
| NLP-BATCH-MOB-001 | Editable per-proposal durations; no writes until final batch approval |
| NLP-DST-MOB-001 | Explicit end range uses elapsed DST duration; conflicting explicit duration requires clarification |
| NLP-BATCH-SEC-001 | Invalid cross-family second write rolls back all events/outbox |
| UNDO-MOB-001 | Preview without mutation, dirty/reverted Save, Cancel and transient Undo |
| Existing natural-language flow | Explicit Delete from saved-event preview |
| FAMILY-HUB-MOB-001 | Direct family screen, owner names/child edits, offline management guidance |
| FAMILY-HUB-SYNC-001 | Encrypted profile edits reach authorized peer; guardian/foreign edits denied |
| CONFLICT-RETIRE-001 | Only causally covered event conflicts retire; stale cards and old snapshots cannot overwrite/reopen |
| AAD-HTTP-001 extension | Real HTTP/PostgreSQL merged resolution removes remote obsolete card |
| CLOUD-BROKER-MOB-001 | Explicit action, fresh-label minimized payload, no pre-approval save |
| CLOUD-BROKER-001 | Exact schema, captured fixed provider request, bounds/errors/no automatic retries |
| CLOUD-API/QUOTA/MIG-001 | Real auth/revocation, atomic multi-connection caps, expiry/account purge and schema round-trip |

Live provider testing deferred explicitly; native device/model compatibility,
real passkeys/protected storage/delivery remain separate acceptance checks.

## Profile navigation and event-entry refinement (BUG-023)

Shared prepared scenarios in `mobile/test/support/profile_navigation_scenarios.dart`
run in the remaining-bugs widget suite and native `regressions` journey. Synthetic
calendarReady SQLCipher state seeds two children and one guardian; add a pet
through the repository only where needed. Direct target pages avoid onboarding.
Each test unmounts UI and disposes its database. No real family/provider data.

| Stable ID | Target and assertions |
| --- | --- |
| PROFILE-NAV-001 | More → separate People/Pets pages; pet/child lists isolated, correct Add actions |
| GUARD-ENTRY-001 | Family offline guardian action explains configured service; no membership mutation |
| GUARD-ENTRY-002 | People Add adult invokes invitation callback; no fake adult profile |
| GUARD-ENTRY-003 | Prepared nonadmin cannot add adults, children or pets |
| ALIAS-AUTO-001 | People Add child blank alias generates distinct validated encrypted aliases |
| EVENT-ENTRY-001 | FAB Describe entry opens unsaved local proposal; Cancel writes nothing |
| DURATION-UI-001 | Hours/minutes reject invalid remainder; 2h30m persists exactly 150 minutes |
| DURATION-END-001 | Compact same-day time, next-day date and DST-zone end previews |
| GUARD-AUTH-001 | Prepared bootstrap with remembered device/no session offers passkey actions; cancel preserves family |

GUARD-AUTH-001 is a widget bootstrap gate, not a real passkey ceremony. Existing
native calendar/adult journeys exercise the new manual choice and color label;
NLP-BATCH-MOB-001 and NLP-DST-MOB-001 retain batch confirmation and DST uncertainty.
Physical connected invitation/passkey/native-model acceptance remains separate.

## P1 voice entry — planned, not implemented or executed

P1-001 inclusion approved 2026-10-14. Prepared synthetic calendarReady/device
fixtures enter the native handoff/proposal directly, without creating family
prerequisites in UI. Unmount/dispose after each run; no real voice/family data in
logs. Physical assistant acceptance is separate from injected native intents.

| Stable ID | Required planned assertions |
| --- | --- |
| P1-VOICE-001 | iPhone Siri/Shortcuts and Android configured assistant deliver an explicit description to an editable Sarti proposal; save only after confirmation |
| P1-VOICE-002 | Cancel, missing/ambiguous time/date/child and interrupted warm/cold launch leave calendar unchanged |
| P1-VOICE-003 | Unlock, current resource access, read-only guardian, account switch and paused recovery gates cannot be bypassed |
| P1-VOICE-004 | Tampered/oversized/injection input rejected or treated only as proposal data; no private context exported, no content in URLs/logs/plaintext queues, no silent cloud call |
| P1-VOICE-005 | Repeated activation cannot silently duplicate writes; approved duration/recurrence/DST semantics preserved |
| P1-VOICE-006 | Real iPhone and Android assistant invoke supported phrases; exact OS/device/account/language/distribution limits and unsupported behavior documented |
| P1-VOICE-007 | Backend/API encrypted-sync regression: authentication, active device, cross-family/resource isolation, replay, idempotency and errors |
| P1-VOICE-008 | Native handoff/API contract validation and generated OpenAPI drift |
| P1-VOICE-009 | Encrypted persistence/outbox/server boundary, wrong-key/tamper and encrypted migration preservation where changed |
| P1-VOICE-010 | Approval-gated local reminders and privacy-preserving notification/push behavior |
| P1-VOICE-011 | Full automated regression on final source, normal builds and both native platform/HTTP-host CI automation |
| P1-VOICE-012 | Static/security/dependency/license/secret checks and sanitized test artifacts |

None of these planned cases has run. Existing parser/widget suites do not prove
Siri/Gemini/Google Assistant compatibility. See ../product/P1-BACKLOG.md.

The mandatory [P1 voice test plan](P1-VOICE-TEST-PLAN.md) defines scope, layers,
fixtures, full-suite gates, existing CI gaps and deferred execution exclusions.
All twelve voice scenarios remain planned; none is claimed implemented here.

## Stage 5 — planned, not implemented

The [Stage 5 test plan](STAGE-5-TEST-PLAN.md) is the canonical mapping for all
17 mandated contract cases plus audit/30-day restoration. Stable new IDs:
S5-ACCOUNT-001/002, S5-AUTH-001, S5-RECOVERY-001, S5-DEVICE-001/002,
S5-ADMIN-001, S5-HOUSEHOLD-001, S5-CHILD-001, S5-PERMISSION-001,
S5-CAREGIVER-001, S5-INVITE-001, S5-ROLE-001, S5-ISOLATION-001,
S5-KEY-001, S5-DELETE-001, S5-OFFLINE-001, S5-AUDIT-001 and S5-RESTORE-001.
Prepared independent synthetic context/SQLCipher/PostgreSQL/device fixtures,
direct target-screen entry and teardown are mandatory. These IDs are plans,
not tests that have passed. Current baseline results are recorded separately
in ../product/STAGE-5-GAP-ANALYSIS.md; physical/provider acceptance is not inferred.
