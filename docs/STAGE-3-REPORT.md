# Stage 3 verification report

- Stage: Stage 3 — AI proposals, email intake, push notifications, and backup/recovery
- Date: 2026-10-11 (original report; see 2026-10-12 remediation below)
- State: incomplete; BUG-001/002 remediated; other open defects and real provider/device verification outstanding

## Features and remediation

Natural-language entry runs a deterministic parser first, optionally uses a
runtime-gated native model, shows an editable proposal, and writes only after an
explicit save. Unsupported devices stay local and deterministic. The optional
Gemini path is disabled by default and requires a versioned disclosure/opt-in;
known child and location values are pseudonymized before transmission.

Email ingress now ends its plaintext persistence boundary inside one backend
request. The service sanitizes and bounds the message, resolves the hashed family
token, then seals the sender/subject/body separately to every currently active
device with its X25519 public key. PostgreSQL stores only digest/expiry metadata
and per-device ciphertext. The authenticated app decrypts locally, attributes
the sender, treats the message as untrusted input, and uses the existing proposal
review. Approval saves the event; dismissal is scoped to the receiving device.

The mobile bootstrap now restores secure sessions, supports native passkey
registration/authentication, provisions offline-created family/calendar IDs
idempotently, runs encrypted synchronization, registers FCM token rotations,
coalesces opaque wake-ups, refreshes email deliveries, catches up on foreground,
and clears expired sessions. Empty backend configuration preserves offline use.

At the original report date, backup envelope primitives passed isolated tests, but the implementation
is not an acceptable recovery feature. Its phrase is not BIP-39, and decrypting
the envelope on a replacement device yields a SQLCipher file whose database key
is unavailable. Fixing this requires a superseding ADR and a reviewed dependency
or platform-independent mnemonic implementation from an established library.

## Changed areas

- Backend: idempotent client-ID family provisioning; encrypted email ingest,
  polling, and dismissal; schema/migration `0004`; PyNaCl; regenerated OpenAPI.
- Mobile: session store; authenticated bootstrap/runtime; API family, email,
  push, and relay wiring; encrypted email inbox and proposal UI; regression tests.
- Engineering: canonical `VERSION`/`BUILD_NUMBER`, ADR-030, release policy,
  version checker/bump command, CI validation, and version tests.
- Documentation: email boundary, API, database, data flow, dependencies,
  operations, security, tests, module catalog, status, and this report.

## ADRs and approvals

| ADR | Result |
| --- | --- |
| ADR-023, ADR-028, ADR-029 | Parser/native AI/cloud-consent rules preserved |
| ADR-024 | Implemented per-device ciphertext boundary as approved |
| ADR-025 | Accepted decision is internally incomplete for replacement-device restore; superseding approval required |
| ADR-026 | Opaque push and OS notification-control decision preserved |
| ADR-027 | Cloud Run + Neon private-beta hosting preserved |
| ADR-030 | SemVer/build-number policy implemented and pushed |

## APIs and migrations

- `POST /v1/families` optionally accepts paired client-generated family and
  calendar IDs and is idempotent for the creating owner.
- `POST /v1/email/ingest` persists only sealed ciphertext and metadata.
- `GET /v1/email/suggestions` returns the authenticated device's ciphertext.
- `DELETE /v1/email/suggestions/{id}` dismisses that device's delivery.
- Migration `0004` removes plaintext email columns, adds device-addressed
  deliveries, and advances `schema_metadata` to 4. The real PostgreSQL migration
  integration test passes.

## Tests executed

| Suite | Result |
| --- | --- |
| Backend unit, security, contract, and PostgreSQL integration | 21 passed; 87.17% branch coverage |
| Migration `0004` / schema readiness | Passed on PostgreSQL 17 |
| Ruff, strict Mypy, Bandit | Passed |
| Flutter unit/widget suite | 76 passed |
| Flutter format and analyze | Passed; no issues |
| Android debug build | Passed; APK produced |
| iOS unsigned debug build | Passed; Runner.app produced |
| Pip-audit runtime dependency scan | Passed; no known vulnerabilities |
| Docker Compose health | Backend and PostgreSQL healthy |
| Release version tests | 3 passed |

Gitleaks is configured in CI but was not installed locally for this rerun. The
generated-contract drift check is rerun after the final documentation update.

## Tests not executed

- Physical iOS/Android passkeys, biometric secret access, scheduled reminders,
  native AI inference, process suspension, and two-device encrypted convergence.
- Live FCM/APNs dispatch, Cloudflare Email Routing delivery, Gemini API request,
  and production TLS/RP/associated-domain configuration.
- Replacement-device backup restore, because the accepted format cannot supply
  the restored SQLCipher database key.

Mocks and successful platform builds do not establish these provider or device
claims.

## Security findings and limitations

- Server email plaintext persistence is removed. A backend operator can observe
  bounded recipient/timing/ciphertext-size metadata but cannot decrypt content.
- Malformed sealed email payloads are discarded, and no email can create an
  event without explicit approval.
- Push contains only `{"type":"sync_available"}` and relies on normal
  authenticated encrypted sync for correctness.
- The Stage 2 child-profile and guardian mobile journeys remain incomplete even
  though backend authorization and relay tests pass.
- The current phrase generator and raw-SQLCipher backup format must not be
  represented as completed recovery.

## Stop condition and next work

Engineering standards require approval before changing ADR-025 or choosing a
material recovery dependency. The next work is to approve and implement that
superseding recovery design, then finish the remaining Stage 2 mobile sharing
journeys and execute provider/device acceptance. Stage 4 must not begin without
explicit approval.

## 2026-10-12 BUG-002 remediation

Approved ADR-031/032 now supersede the recovery defects described in the original
report. The shipping owner backup UI, authenticated opaque relay, automatic
replacement-device discovery, v2 SQLCipher key envelope, and protected staged
activation are implemented. See [BUG-002 verification](testing/BUG-002-VERIFICATION.md)
for changed areas, exact checks, security controls and remaining physical-device
limitations. Stage 3 remains unaccepted; BUG-003/004/005 are still open. Do not
start Stage 4 or another defect without explicit approval.

## 2026-10-12 BUG-003 remediation

Encrypted child-profile creation and distribution, explicit sharing with existing
calendar guardians, signed sealed-key exchange, epoch/retry handling, safe
profile/event ordering and receiving labels/colours are implemented under
ADR-020/021/022. SQLCipher schema v6 is tested; PostgreSQL remains at 0005.
See [BUG-003 verification](testing/BUG-003-VERIFICATION.md) for changed files,
APIs, migration details, exact tests, security findings and platform limits.
Stage 3 remains unaccepted: BUG-004/005/011 and newly discovered High-severity
BUG-010 remain open. Device replacement currently revokes the old phone without
advancing resource epochs. Obtain explicit approval before the next defect;
do not begin Stage 4. Android-to-iOS backup execution remains deferred by user.
