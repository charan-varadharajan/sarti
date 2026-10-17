# Stage 5 household milestone — verification

Updated 2026-10-17. Development version 0.7.0+8. Accepted ADR-041; Stage 5 remains incomplete.

## Behavior

- More → Households selects independent local calendars or creates/joins another
  household progressively. Selection persists in SQLCipher; no implicit key,
  child or event sharing. Repeated guardian identity has separate scoped profiles.
- Async sync/recovery/policy/reminder work stays bound to its starting household.
  Stale event/native/email editors cannot create into another selected household.
- Explicit interrupted-upload review checks current-device metadata-only receipts
  after lost authority. Original payload/vector/envelope is quarantined unchanged;
  expired delivery evidence remains unknown. Other households use the actual next
  server sequence. Unresolved intent is never automatically republished.
- Missing-family encrypted snapshot imports atomically into the same live store,
  preserving other households/private keys, identity, counters/cursors and in-flight
  uploads. Collision, corruption, wrong phrase or foreign family leaves it unchanged.
- Sealed email v2 binds household/suggestion; UI filters and checks both. Delivery/
  listing requires live calendar resource rights, suitable role and unexpired
  membership, excluding care-calendar-only recipients.

## Changes and approvals

BUG-026/027/028/029; no new external service/dependency/cryptographic primitive.
Local v11 adds encrypted original-envelope/receipt provenance; v12 scopes guardian
identity and pickup/dropoff foreign keys. Actual legacy encrypted migration and
rollback coverage protects keys, relationships and exact pending bytes.
PostgreSQL stays 0013. New `POST /v1/sync/sequence-review` and additive email
`family_id` response contract; generated OpenAPI updated. Architecture/API/database/
security/modules/operations/scenarios/traceability/status/changelog updated.
Version bump promotes accumulated entries; no public/store release tag.

ADR-041 approval already covers these changes. Approved retention remains:
expired calendar bodies can be removed while unresolved original intent stays
protected separately; quarantine never silently extends calendar retention.

## Checks on final source

Final gates pass on version 0.7.0+8:

| Check | Result |
| --- | --- |
| Flutter full unit/widget suite | 250 pass; two explicit host-only skips |
| iOS registered native journeys | nine journeys, 107 checks pass |
| Android registered native journeys | nine journeys, 107 checks pass |
| Isolated PostgreSQL backend/API/security/contracts | 95 pass; 92% reported coverage; both HTTP/Dart hosts enabled and executed |
| Migrations and generated OpenAPI contract | pass; PostgreSQL 0013, local v12 |
| Android debug APK / unsigned iOS debug build | both pass |
| Dart analysis / Ruff format+lint / Mypy / Bandit | pass |
| Docker isolated live/ready/maintenance smoke | pass; test volumes torn down |
| Tooling / canonical version integrity | 11 tests pass; 0.7.0+8 consistent |
| Backend locked dependency / hosted Dart advisory checks | no known issues; 135 Dart packages checked |
| Offline pinned Gitleaks / whitespace checks | pass; final staged patch rescanned before commit |

The failed calendar fixture was corrected and rerun (eight pass); four previously
passing iOS groups had unchanged application/scenario source, then the remaining
four ran. All nine are verified on final application source; the first failed
whole invocation is retained as failed evidence, not relabelled a pass.
Both unit-suite host-only skips are executed through the separate backend HTTP/
Dart hosts. Commands: `flutter analyze`, `flutter test --reporter json`, shared
`./test --ios|--android` allowlist (iOS selected continuation after fixture fix),
`flutter build apk --debug`, `flutter build ios --debug --no-codesign`, isolated
Alembic upgrade/full pytest with both host flags, `make backend-check`, isolated
Docker smoke/maintenance, scripts unittest/version checks and locked dependency/
offline secret checks. Logs: `test-results/stage5-households-final-*.log` and
`stage5-backend-full.log`. Four task-created PostgreSQL fixture databases removed;
development data preserved. No provider, hosting or user signing changes.

Previously verified foundation: commit 76cc245, Flutter 229 pass/2 host-only skips,
backend 93 pass, iOS/Android 82 checks each, all documented foundation gates pass.

Additional targeted checks pass: household/widget/runtime/invitation,
actual legacy migration/rollback, encrypted occupied-store import, sequence receipt
security and email PostgreSQL/sealed-box isolation; dependency checks report no
known issues (backend runtime lock, 135 hosted Dart packages). Offline pinned
Gitleaks final staged patch scan passes.

Meaningful intermediate failures were corrected and rerun: stale-editor fixture
omitted manual entry; duplicate reminder scheduling; legacy recovery cleanup pause;
child UPSERT conflict target accidentally broadened while scoping guardians;
incomplete old-v2 migration fixture missing original core tables; email fixture
missing new sealed-family binding; experimental quarantine retention guard changed
approved behavior. The guard was corrected, not the retention acceptance test.
Final spot check of retention/receipt preservation: five pass. The iOS run later
found CAL-MOB-001's wall-clock date assumption (BUG-029); fixture follows the
actual saved date, retaining all persistence/recurrence/reminder assertions. An earlier native
pipeline was explicitly interrupted for that review; it is not a completed pass.

## Boundaries and remaining work

No live email/AI/provider call, hosting/billing activation, physical phone/passkey/
protected-storage/notification-delivery acceptance or Android→iPhone BACKUP-XPLAT-002
run. Real SQLCipher/libsodium and PostgreSQL evidence does not prove those boundaries.
Remote GitHub CI execution is separate from local checks and remains unverified.
Legacy unbound email v1 fails closed and may need resubmission; no guessed attribution.
Invalid legacy cross-household pickups roll back and need explicit repair.
Quarantined original intent is preserved; fresh authorized re-publication is not
implemented automatically. Existing-family overwrite and occupied personal snapshot
restore are unavailable. Historical downloaded copies cannot be remotely erased.

Remaining authorized Stage 5: role administration/impact/step-up/audit UI and
legacy mutation integration; caregiver reviewed independent copies; guardian-assisted
family-only recovery; authorized export; account/context closure/purge; retention-
aware recoverable manual event deletion/restore; complete acceptance traceability.
No Stage 6 starts from this milestone.
