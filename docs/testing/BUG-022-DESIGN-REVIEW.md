# BUG-022 design review and reproduction

Date: 2026-10-13 (America/Vancouver). Historical pre-fix baseline: 0.3.0+3.
This records the original design review and expected-red evidence. Maintainer
subsequently approved ADR-040; the implementing change and current verification
are recorded in BUG-022-VERIFICATION.md. At the time of this baseline no runtime
recovery behavior, API, schema or retention gate had changed.
Local iOS signing edits are preserved. No next bug or stage is started.

## Confirmed failure

Prepared source and replacement installations use independent SQLCipher stores,
real v2 snapshot encryption, staged activation and libsodium-authenticated relay
messages. The source has an unsent edit at its second causal version and two
historical key epochs. The replacement uses a new device ID and a simulated
freshly authorized epoch 3 key. No source credential or pending envelope should
be uploaded under the former identity.

- **RECOVERY-CONT-001 fails:** a retained epoch 1 ciphertext cannot decrypt after
  family restore, despite availability of the independent current epoch 3 key.
  Actual error: `The resource key epoch is unavailable.`
- **RECOVERY-CONT-002 fails:** readable epoch 3 guardian ciphertext replaces the
  restored unsent title instead of preserving concurrent alternatives.
  Expected `Restored offline change`; actual `Guardian concurrent change`.

These failures execute through BackupRecovery snapshot/stage/activate and
SyncEngine, not just direct queries of missing tables. The relay/current grant
are synthetic. No real backend authorization, passkey, physical device or
provider compatibility is inferred from them.

## Checks executed

| Check | Result |
| --- | --- |
| Focused backup/recovery + calendar/sync + encrypted migration baseline | 14 passed |
| Opt-in desired-behavior reproduction | 2 failed as expected on unchanged implementation |
| Reproduction formatting | PASS |
| Flutter static analysis | PASS, no issues |
| Default opt-in gating | PASS, both reproduction cases explicitly skipped without the define |
| Whitespace | PASS, `git diff --check` |

Baseline:

```sh
cd mobile
flutter test test/backup_recovery_test.dart test/calendar_and_sync_test.dart test/retention_migration_crypto_test.dart --reporter expanded
```

Reproduce explicitly (expected failure until ADR-040 implementation):

```sh
cd mobile
flutter test test/family_recovery_continuation_test.dart --dart-define=SARTI_RUN_BUG022_REPRO=true --reporter expanded
```

Default runs skip these two desired-behavior tests rather than asserting the
unsafe behavior as correct. This does not close BUG-022 or establish release
readiness. After architectural approval, remove the opt-in gate and require both
regressions to pass. Ignored logs: `test-results/bug022-baseline.log`,
`bug022-reproduction.log`, `bug022-analyze.log`, `bug022-default-gating.log`.
Only failed blocks/result summaries were inspected; successful logs were not analyzed.

## Concrete proposal and required approval

[ADR-040](../architecture/adr/040-family-recovery-continuation.md) preserves
validated family history/keys, keeps fresh identity/authorization boundaries,
quarantines recovered pending intent for review and re-enveloping, and resumes
retention only after catch-up and explicit history review. It preserves adult-
private exclusion, backup v2 crypto, server key custody and seven-day relay TTL.
It includes incomplete legacy backups, interruption and unavailable expired
history as explicit fail-safe/accuracy cases.

ENGINEERING-STANDARDS.md requires: “Stop and obtain approval if an accepted ADR
must change”. Here ADR-032 currently explicitly requires clearing the very keys
and causal state that cause this failure; ADR-039 keeps the recovery cleanup
pause. The proposal must be approved before changing those accepted rules.

No implementation/API/migration/native/security-provider/full-suite acceptance
is claimed in this design-only turn. Native and full HTTP/security/backup gates
are required by the proposal after implementation. Android→iOS backup portability
remains deliberately unrun. Next action: review/approve ADR-040, then implement
only BUG-022 and its documented tests.
