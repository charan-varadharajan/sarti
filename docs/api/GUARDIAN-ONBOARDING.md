# Guardian onboarding — BUG-004

ADR-019/020/022/035 govern this P0 flow. A signed-in owner opens **Family
guardians**, creates an invitation and shares it through the OS sheet (text,
email or an installed app), copies it, or shows the QR code. No message is sent
automatically. The other parent opens the installed-app link, scans it with a
system QR reader that supports the scheme, or pastes it after passkey sign-in.
They explicitly accept, compare the displayed code with the owner, and wait.
The owner reviews the same code and resource access, enters the local guardian
name and approves. The recipient refreshes status and opens the decrypted
calendar after the encrypted initial handoff completes. No recovery-key exchange
is part of guardian enrollment.

```mermaid
sequenceDiagram
    participant O as Owner phone
    participant API as Sarti API
    participant G as Guardian phone
    O->>API: Create invitation (owner session)
    API-->>O: One-use token, 48-hour expiry
    O-->>G: Share / copy / local QR (token only)
    G->>API: Explicit authenticated acceptance
    API-->>G: Pending; no resource content/grants
    O->>API: List pending device public keys
    O-->>G: Compare displayed verification code
    O->>API: Approve pinned device and resource permissions
    API-->>O: Active membership, captured relay baseline
    O->>API: Signed per-device sealed keys and scoped ciphertext handoff
    G->>API: Refresh authorized grants / relay above baseline
    G->>G: Verify, decrypt, preserve versions and display calendar
```

## API additions and changes

- `GET /v1/families/{id}/invitations`: owner-only, at most 100 recent entries;
  UUID/state/expiry, accepted adult/current active device public keys and current
  resource permissions. Never returns old tokens/digests or display names.
- `DELETE /v1/families/{id}/invitations/{invitation}`: owner-only cancellation
  of open/pending invites; repeat cancellation is safe. Approved membership
  removal uses the guardian endpoint instead. No key access is granted.
- Approval accepts `expected_device_id` and `expected_key_digest`. The new client
  always supplies both; omitted values retain compatibility for older callers.
  Device changes or non-identical retries return 409. Permissions must be a
  nonempty, duplicate-free subset of live family resources; unknown scope is
  rejected. The UI gives family-profile read access, calendar read/write choice
  and optional per-child read access. It never grants guardian admin access.
- Pending expiry is checked again on approval. Accepted tokens cannot be reused.
  A cancelled/expired/removed guardian can enter pending state through a fresh
  owner-created invitation; stale invitations cannot revive/revoke that new one.
- Family listing returns effective resource permissions and `sync_start_cursor`;
  pending memberships expose no resource list. Active guardians see only
  permitted live resources. Sync reads enforce the starting sequence even with
  a caller cursor of zero. Existing owners/guardians default to baseline zero.
- Removing a guardian retires its pending/approved invitations and rotates keys
  using the existing lifecycle. Historical copies are outside remote erasure.

All completion requests use authenticated POST JSON; the token never enters an
API URL/query. QR/link generation is offline; creation, acceptance, approval and
handoff need the configured authenticated Sarti service. Link consumption never
changes that service address. Deployment uses `SARTI_API_BASE_URL` at build time;
an offline-only developer build cannot enroll a guardian.

## Encryption and retry behavior

Current allowed children are re-published inside their independent resource
ciphertext. Calendar events and tombstones retain IDs, durations and causal
vectors; no user event is edited by sharing. A family-profile `household_shared`
operation contains only encrypted family name and guardian profiles, validates
scope and bounded fields, rejects concurrent profile replacement, and marks the
local handoff ready after the earlier queued state. A nameless child placeholder
preserves calendar assignments when its separate profile is not shared.

The initial family-profile epoch may be claimed by its owner only if unclaimed;
subsequent rotation/import follows the existing signed grant protocol. Pending
members get no grants. Read-only access is reflected in the UI and cached inside
SQLCipher for offline use; every server write remains independently authorized.
Progress references retained outbox operation IDs, making lost-response retries
safe and allowing explicit retry if recovery cleared the old outbox. Existing
open event conflicts must be resolved before initial sharing; no alternative is
silently chosen. BUG-017 stale remote conflict cards remain a separate defect.

## Platform and retention boundaries

The QR is displayed in Sarti; scanning uses a compatible system camera/QR app.
There is no in-app scanner or web/app-store landing page. The custom scheme
requires Sarti to be installed; paste is the fallback where messaging clients
or QR readers do not open it. Share/copy exposes the expiring token to the
explicitly chosen transport/clipboard. Verify the device code before approval
if the link may have been forwarded. HTTPS universal links require a separately
configured production domain and are not claimed enabled.

Handoff operations expire in seven days like all relay data; a guardian who
misses that window needs an authorized recovery/handoff workflow. This does
not grant access to an owner's full encrypted backup. Physical passkeys, native
camera scanning, cold/warm OS link delivery, real share/clipboard apps and two
physical phones require platform validation separate from mocks and builds.
