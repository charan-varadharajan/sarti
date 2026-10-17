# Stage 5 scoped administration — ADR-041

Status: foundation implemented, full Stage 5 journey incomplete. Accepted
2026-10-16. Generated `backend/openapi.json` is the wire schema. All endpoints
require an unexpired bearer session on the adult's active phone. Only opaque
identifiers, role/grant metadata and ciphertext are stored; names are not accepted.

## Current-device confirmation

`POST /v1/auth/step-up/options` binds action, nullable family ID, target UUID and
expected ACL revision to the current adult/device/session. Actions are
`admin.change`, `permissions.change`, `membership.revoke`, `household.close`,
`account.delete`, `export`, `event.restore`. Only account deletion has null family
scope, and its target must be the authenticated adult. A context action requires
current active membership and the exact ACL revision. This membership check does
not grant permission to perform the action.

The current native passkey adapter signs the challenge. Send its assertion to
`POST /v1/auth/step-up/complete`. Existing WebAuthn verification requires correct
RP/origin, challenge, user verification and credential ownership. Successful
verification returns a single-use proof; only its SHA-256 digest persists. Both
challenge and proof expire five minutes after issuance. At most 20 pending
challenges per session are retained. Responses have `Cache-Control: no-store`.

A mutation consumes its matching proof in the same database transaction as its
permission checks and changes. Wrong session/device/action/target/context/revision,
expired assertions, reused completion and reused proof fail. Failure rolls back
consumption. This is a distinct ceremony from phone replacement: it never creates
or revokes a phone/session and never sends device encryption secrets.

## Contexts, membership and audit

- `POST /v1/contexts`: typed household/classroom/activity/school; creates the
  corresponding administrator and explicit grants on profile/calendar/audit
  resources. No real-world employment or legal guardianship is verified.
- `GET /v1/contexts`: only the caller's live active/pending context assignments.
- `GET /v1/contexts/{id}`: active membership and explicitly readable resources;
  no implicit private, other-child or cross-context access.
- `GET /v1/contexts/{id}/members`: current context administrator only. Returns
  opaque roles/status/expiry, public device keys/fingerprint and public-resource
  grants. Revoked recipients have no current-device entry. Private grants excluded.
- `PUT /v1/contexts/{id}/members/{adult}`: replaces that existing active member's
  public grants and role/status/expiry. Requires expected ACL revision, matching
  action proof, current recipient-device/fingerprint pin for non-revocation, and
  encrypted audit envelope. Never enrolls an arbitrary nonexistent account.
- `GET /v1/contexts/{id}/audit`: current administrator plus explicit audit-resource
  read permission; bounded to the latest 100 unexpired ciphertext records.

Role changes use `admin.change`; same-role grant changes use `permissions.change`;
revocation uses `membership.revoke`. Context lock, ordered adult/resource locks,
current authority and last permanent active administrator protection apply before
mutation. Concurrent self-demotions cannot both succeed. Administrators cannot
assign a role belonging to another context kind or grant a resource they cannot
administer. Adult-private resources remain author-only. Caregivers can receive
read-only child-profile/care-calendar grants, never the entire household calendar,
profile, audit resource or backup through this API. Volunteer/subscriber grants
are read-only. Administrator promotion alone adds no resource key or child grant.

Lost public grants advance only affected live resource epochs. Expiry reconciliation
commits revocation/rotation before routing an authenticated request, including
before a denied request; publishers in the same context also trigger it. This
prevents expiry being undone by a later authorization failure. Device replacement
and publication share resource locks. Previously downloaded data cannot be erased.

The audit uses existing protocol-2 XChaCha20-Poly1305 metadata/ciphertext fields,
with author device recorded separately. It is not a calendar relay upload and
its sequence is not allocated from the calendar device sequence. Validate bounded
nonce/ciphertext/digest/resource/current epoch, then atomically commit ciphertext
with authoritative action/target/outcome/ACL revision. The server cannot verify
the decrypted narration; a future client audit viewer must compare it against
these authoritative fields. Detailed records expire after 30 days. An exact
operation-ID/body retry returns the saved outcome while caller remains authorized;
a changed body/device/context/target conflicts. Audit expiry does not extend
proof validity or calendar relay retention.

## Errors and remaining integration

Structured 401: invalid session/device or confirmation; 403: insufficient scoped
role/resource authority; 404: inaccessible context/member/resource; 409: stale
revision/device pin, final administrator, changed retry; 422: malformed/extra
fields. Errors/logs do not echo assertions, proofs, ciphertext or private content.

The new API is not evidence that Stage 5 is complete. Legacy invitation/removal,
backup/export routes and shipping administration UI still need their approved
step-up/audit coordination. Caregiver reviewed-copy publication, scoped snapshot
import, account/context closure and recoverable deletion remain pending. Do not
claim existing legacy routes enforce these new safeguards. No provider/physical
passkey compatibility is established by the synthetic verifier tests.


Legacy invitation approval now independently checks the administrator's grant
on every requested resource (BUG-025); a fresh ordinary invitation resets a
revoked member to pending guardian and clears former expiry. It does not retain
administrator authority. These checks prevent scoped-role escalation without
claiming the pending operation-bound step-up/audit integration is complete.
Whole-family backup operations require read authority over every public live
resource (BUG-024); administrator role alone is insufficient. Cached calendar
write controls also require explicit write/admin permission.

Expired audit/confirmation records and memberships also have a transactional
maintenance entry point, `python -m sarti_backend.households.maintenance`. It
outputs counts only and is exercised by PostgreSQL tests and isolated Docker
smoke. Scheduling and purge-timing acceptance remain deployment work; see the
operations runbook. Read-time expiry is enforced without waiting for a scheduler.


## Interrupted upload after lost context authority (BUG-026)

`POST /v1/sync/sequence-review` accepts operation/family/resource UUIDs, original
sequence and ciphertext digest in the authenticated body. It rechecks current
session/device under resource→device locks and requires lost write authority.
It returns only the caller's device ID/high-water and matching own operation
receipt: accepted, not_accepted (sequence never reached), or unknown (receipt
expired/missing with high-water already reached). No other-device receipt,
ciphertext, profile or key is returned, and no sequence is mutated/reserved.
Bindings must match an available own receipt. Responses are no-store.

The shipping Households card requires explicit preservation review and rejects
changed local work/session/device/receipt. Exact original envelopes and payload/
vector are quarantined in local v11, not discarded/renumbered. Other contexts can
then synchronize at server high-water+1. Quarantined work is not automatically
re-published if access later returns. Existing relay TTL is unchanged.
