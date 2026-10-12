# Cross-platform encrypted backup scenarios

## Repeatable execution

Use two booted disposable development devices. The runner installs a test app;
run the normal app again afterwards if needed. Existing `sarti.db` is untouched;
prepared data lives in a separate `backup-portability-scenario` directory.

```sh
python3 scripts/test_backup_ios_android.py \
  --ios-device A351256A-6255-4285-A1AE-5624594A08FD \
  --android-device emulator-5554 \
  --adb "$HOME/Library/Android/sdk/platform-tools/adb"
```

The default direction is `ios-to-android` (`BACKUP-XPLAT-001`). To run the
reverse scenario later, explicitly select `android-to-ios` (`BACKUP-XPLAT-002`):

```sh
python3 scripts/test_backup_ios_android.py \
  --direction android-to-ios \
  --ios-device A351256A-6255-4285-A1AE-5624594A08FD \
  --android-device emulator-5554 \
  --adb "$HOME/Library/Android/sdk/platform-tools/adb"
```

**BACKUP-XPLAT-002 is added but NOT RUN, as requested by the user.** It uses the
same prepared fixture, exact-byte/digest verification, wrong-phrase rejection,
restored content and key/identity assertions, with Android exporting and iOS
restoring. Export readiness is signalled only after the file and UI assertions
finish. Neither direction was rerun after generalizing the shared runner.

The original iOS-to-Android flow has two native executions, connected by the host runner:

1. Prepare an encrypted iOS SQLCipher database with a synthetic child, guardian,
   weekly event, pickup assignment, notes, colour and reminder offsets.
2. Enter the backup screen directly, acknowledge the public test phrase, and
   explicitly create an encrypted snapshot using the shipping backup service.
   Write the actual `.srtbk` in the iOS app's sandbox.
3. Copy only that ciphertext file through a temporary host directory into Android's
   app sandbox. Compare bytes and SHA-256; the database key is never exported
   outside the recovery envelope. This transfer replaces network transport only
   for this test; the product does not require manual file handling.
4. Open a new Android SQLCipher installation with an independent random key and
   enter the restore screen directly. Confirm a wrong valid phrase fails without
   adding local family data, then restore with the correct public test phrase.
5. Stage, close, activate, reopen under the recovered key, and verify family,
   child, colour, event/notes, timezone/start, recurrence, pickup, reminders,
   database integrity, fresh identity and cleared stale synchronization keys.
6. Clean up disposable database directories, ciphertext transfer files and the
   temporary host directory. App/support secrets for real families are unused.

The fixed phrase is a public BIP-39 test vector and must never secure real data.
Only synthetic fixture data is used. No product API, schema, dependency or ADR
changes are needed for this scenario.

## Verification boundaries

This establishes real cross-platform native SQLCipher/envelope file compatibility
on the tested iOS simulator and Android emulator. The secret-store journal is an
in-memory test adapter. Passkey login, device replacement authorization, network
relay/TLS, physical Keychain/Keystore, OS interruption and notification delivery
are separate tests. Reminder settings are checked; delivered reminders are not.
The opposite Android-to-iOS direction now has a separate scenario; its runtime
compatibility is unverified until explicitly run.

## Latest execution

Historical `BACKUP-XPLAT-001` execution passed on 2026-10-12 (commit `e9e504f`,
before the unexecuted shared-runner generalization):

| Boundary | Actual result |
| --- | --- |
| Source | iPhone 18 Pro simulator, iOS 27.0; export phase passed |
| Destination | Medium Phone Android emulator, Android 15 / API 35; restore phase passed |
| Native file | v2 `.srtbk`, 135,261 bytes |
| Transfer integrity | Exact bytes compared by host; digest checked inside Android test |
| Ciphertext SHA-256 | `95420c211c04313ee2a10cf5b90709d6e84b636e9d32fbde639d2cbfd559298f` |
| Encryption/decryption | Actual native libsodium + SQLCipher; independent destination key replaced by recovered key |
| Restored content | Family, child/colour, weekly event, notes, start/timezone, duration, pickup and reminder settings all passed |
| Negative case | Wrong valid phrase rejected; empty destination family data unchanged |
| Post-restore security | New identity preserved; stale keys/outbox and pending journal absent |
| Final runner | Exit 0; one passing integration test on each platform |

Initial harness attempts found an invalid synthetic alias and Flutter's automatic
post-test app removal. The alias was corrected and transfer acknowledgements
were added; the final complete run above passed. No production defect or runtime
behavior was changed. Static formatter/analyzer, Python runner lint and normal
mobile regression results are recorded alongside this run in `STATUS.md`.

This remains simulator-to-emulator validation. Physical iPhone-to-Android,
passkey-to-download, native protected storage, production relay, process-kill,
and delivered reminder tests were not performed. Backend/API/migration suites
were not rerun for this test-only change; their implementation is unchanged.
