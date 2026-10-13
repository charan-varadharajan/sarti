# ADR-035: Guardian invitation sharing and scoped encrypted handoff

- Status: Accepted within the approved BUG-004 implementation scope
- Date: 2026-10-13
- Authorization: Maintainer approved guardian onboarding with native share/copy
  and explicitly included QR in this fix. Package versions and coordination
  details below are reviewed implementation choices, not previously approved
  provider selections. No existing ADR is superseded.

## Decisions

Use pinned `share_plus` 13.3.1 for the OS share sheet, `qr_flutter` 4.1.0 for
local QR rendering and `app_links` 7.2.2 for installed-app custom-scheme links.
The installed app handles only `sarti://invite#<43-character base64url token>`;
it never derives an API host, auto-accepts or changes permissions from a link.
The fragment contains only the ADR-019 random expiring token. No names, calendar
content, encryption keys or recovery phrase are in it. App tokens are memory-only;
server storage remains token digest/expiry/state only. Paste-code fallback is
available. The system camera/QR reader may open an installed Sarti; no in-app
camera SDK or contact/message/inbox permission is introduced. App-not-installed,
HTTPS universal-link hosting and provider-specific linkification are not claimed
implemented. Production link-domain selection remains unresolved.

Acceptance is explicit after authentication and creates pending membership.
Before approval the owner compares a public-device verification code shown on
both phones, chooses calendar read/write and child-profile read permissions,
and supplies the guardian's local display name. No private name goes to the
server. Approval pins the current device UUID and SHA-256 digest of signing
then encryption public keys; a changed device requires review again. The code
is the first 16 digest hex characters grouped in four blocks for comparison,
not a decryption key. Full digest pinning rejects a device/key change between review and approval commit.
This supplements ADR-019/020 rather than changing authentication or primitives.

## Initial state and retention

Keys alone cannot recover expired ciphertext. Approval locks adult/resource
metadata consistently with replacement, records a starting relay sequence and
activates only explicitly authorized resources. Owner synchronization drains
before approval and again before preparing the handoff. Server download floors
exclude pre-approval history; reset local cursors cannot bypass the floor.
Existing members retain baseline 0. Migration 0007 adds only that metadata;
downgrade refuses to remove a nonzero baseline. Resource locks serialize floor
capture with current uploads.

The owner publishes current allowed child profiles under their own keys,
calendar events/tombstones with unchanged IDs/content/version vectors under
the calendar key, then an encrypted `household_shared` profile under the family
profile key. That final profile marks the local handoff ready. Family names and
guardian names never enter calendar or server plaintext. Initial family-profile
key establishment uses the existing serialized signed self-grant protocol;
missing established keys are never fabricated. Ordinary seven-day relay
retention, exact retries and revocation epochs still apply; no permanent
server snapshot or backup authority is added for guardians.

A durable SQLCipher progress record references queued operation IDs. Retries
reuse them; an orphaned record after old-identity outbox clearing permits a new
explicit handoff. A failed upload remains pending. Exact already-approved API
retries require identical permissions; they cannot expand access. The UI offers
finish/retry for interrupted sharing. Initial sharing waits for existing open
calendar conflicts to be resolved instead of dropping alternatives. A guardian
offline beyond retention still needs the approved authorized recovery path;
this is not an indefinite snapshot service.

The client stays within one local family. Read-only guardians can browse/view,
but cannot create, edit, delete, resolve conflicts or add children through the
UI. Encrypted cached access supports offline behavior; server authorization is
always authoritative online. Removal revokes membership/permissions, retires
old invitation approvals and advances epochs before future grants. Earlier
copies cannot be erased. Cancellation of pending invitations grants no keys.

## Dependencies and limits

Direct licenses: share_plus BSD-3-Clause, qr_flutter BSD-3-Clause, app_links
Apache-2.0. Resolver lock records 14 newly added packages; app_links adapters are
Apache-2.0, other additions use BSD-style permissive licenses. Package source
review found no incoming-token logging or content telemetry in targeted native
paths. QR rendering is local and uses no network. Sharing intentionally hands
only the invitation text to the OS/user-selected app. OSV returned no listed
advisories for all 14 exact versions on 2026-10-13; this is not proof of absence.
Share requires Flutter >=3.38.1, iOS >=13 and AGP >=8.12.1; current SDK/build
settings meet these declared minimums. Native builds/tests remain required.

Sources: [share_plus](https://pub.dev/packages/share_plus),
[qr_flutter](https://pub.dev/packages/qr_flutter),
[app_links](https://pub.dev/packages/app_links).

Prepared widget/native and real HTTP/PostgreSQL/Dart tests must cover pending
isolation, fingerprint pinning, permission scope, malformed/replayed/expired/
cancelled invitations, retries, encrypted retained-state handoff, read-only UI
and revocation. Mocks do not prove native camera, message delivery, passkeys,
protected storage, universal links or physical-phone compatibility.
