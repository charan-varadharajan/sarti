# BUG-010 — Replacement epoch verification

Date: 2026-10-12. Status: **Failed-test spot fixes pass; full-suite rerun pending.**

## Scope and approvals

The maintainer authorized BUG-010 under accepted ADR-020: fix, add applicable
security/regression tests and run them, but do not inspect failure logs. No ADR
was superseded, new dependency introduced or other bug addressed. ADR-019
single-active-phone enforcement and ADR-032 recovery boundaries are preserved.

## Changes

- `households/device_replacement.py` exposes the metadata-only scoped epoch
  transition; auth serializes on the adult and locks affected resources in
  stable order. Active owners rotate all live family resources; guardians rotate
  explicitly permitted resources. Pending/revoked membership, deleted resources
  and deleted families are excluded. Epochs, revocation, replacement registration
  and session creation commit or roll back together.
- Sync uploads share the resource lock with replacement; stale unaccepted
  envelopes fail. Key grants recheck active granter state after the lock.
  Exact accepted-envelope receipts retain existing idempotency semantics.
- Mobile retains the existing signed sealed-box/first-granter protocol. A
  restored admin without historical keys may claim an unclaimed advanced epoch;
  a missing initial or established key is never fabricated. The server arbitrates
  concurrent claims; accepted self-grants recover from lost responses.
- Auth endpoint description/OpenAPI regenerated. API, key lifecycle, module,
  server database, scenario, security, bug, status and changelog records updated.
  No SQLCipher/PostgreSQL schema or migration, backup format or UI change.

## Added tests

`backend/tests/integration/test_device_replacement.py` uses prepared accounts,
real PostgreSQL transactions, stubbed WebAuthn verification and independent
PyNaCl crypto. It covers scoped owner/guardian epochs, pending/unrelated-family
isolation, old-session rejection, challenge replay, stale grants/writes,
active-only directory, sealed delivery, old-phone key rejection of future
ciphertext, rollback/retry and concurrent distinct-passkey replacements.

`mobile/test/device_replacement_test.dart` uses independent real SQLCipher and
libsodium logical devices with the controlled relay. It covers revoked-device
old-key rejection, fresh restored-admin epoch initialization and future writes,
lost self-grant response recovery, and refusal to invent initial/established
keys. The shared fixture gains a one-shot lost-grant-response injection.
Stable IDs and prepared entry/teardown are in TEST-SCENARIOS.md.

## Executed checks

All output saved under ignored `test-results/bug010-*.log`. Only process exit
status was inspected; no test counts, failure identities or diagnosis inferred.

| Check | Result |
| --- | --- |
| Isolated local PostgreSQL `sarti_bug010` setup | PASS |
| `alembic upgrade head` | PASS |
| Full backend `pytest --cov=sarti_backend --cov-report=term-missing` (unit/API/security/contracts/migration) | PASS |
| Ruff format check and lint | PASS |
| Strict Mypy | PASS |
| Bandit | PASS |
| `pip-audit -r requirements-runtime.lock` | PASS |
| Dart format check | PASS |
| `flutter analyze` | PASS |
| Full `flutter test --coverage --reporter expanded` | **FAIL**, exit 1 |
| OpenAPI generation | PASS; committed description updated |
| Version integrity (`0.1.0+1`) and `git diff --check` | PASS |
| Pinned Gitleaks staged-diff scan | NOT RUN: automatic approval review rejected passing staged source to a third-party Docker image |

The initial execution did not inspect logs or retry failures.

## Authorized failed-test spot fix

The maintainer subsequently authorized inspecting only failed tests and making
spot fixes. Only the three failure blocks were extracted from the saved Flutter
log. `REPLACE-SYNC-001` and `REPLACE-SEC-002` lacked timezone initialization in
this test isolate; suite setup now initializes the bundled database.
`REPLACE-SEC-001` incorrectly expected resource preparation to propagate a 403,
although preparation intentionally skips inaccessible resources. It now asserts
the directory request is denied and preparation leaves the new epoch key absent
and the retained historical key unchanged. Old-key decryption rejection and
active-only grant assertions remain intact. No application behavior changed.

- Only those three previously failing tests were rerun with
  `flutter test test/device_replacement_test.dart --name
  'REPLACE-(SEC-001|SYNC-001|SEC-002)' --reporter expanded`: **PASS**, exit 0.
- Formatting of the edited test file and `git diff --check`: **PASS**.
- Logs: `test-results/bug010-spot-tests.log`, `bug010-spot-format.log`.
- Full Flutter suite, backend checks and native tests were not rerun in this
  follow-up, as requested. The initial full-suite failure remains historical
  evidence, not a claim that the corrected full suite passes. BUG-010 remains
  open pending full verification; the secret scan is still unexecuted.

## Limits and next action

No native simulator/emulator rerun or shipping build performed after the failing
Flutter suite. Neither backup portability direction ran; Android-to-iOS remains
explicitly deferred. No new device authentication bypass was added.

Physical passkeys, Keychain/Keystore, real recovery UI interruptions, production
network transport and two physical phones remain unverified. The controlled
relay and stubbed WebAuthn verifier do not establish these guarantees.
Historical copies cannot be erased; missing historical keys/snapshots still fail
closed. The server never receives plaintext resource or recovery keys.

Do not move to another defect or Stage 4 automatically. Full verification and
the blocked secret scan remain outstanding; scoped failed-test fixes pass.
