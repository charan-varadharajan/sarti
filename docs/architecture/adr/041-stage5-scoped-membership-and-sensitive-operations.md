# ADR-041: Stage 5 scoped membership, recovery and sensitive operations

- Status: Accepted by maintainer 2026-10-16; implementation in progress
- Date: 2026-10-16
- Authority: Maintainer requested Stage 5 product scope in the attached contract.
  Maintainer explicitly approved this complete ADR after reviewing the proposal.
- Supersedes: ADR-019 owner-only invitation approval; ADR-022 single
  owner and owner-wide household authority; ADR-035 single local family and
  enrollment restrictions; ADR-032/038 single-family database/recovery assumptions;
  ADR-039 only for explicitly recoverable manual deletion as specified below.
- Preserve: Flutter/Riverpod, FastAPI/PostgreSQL, SQLCipher, passkeys, one active
  phone per adult, libsodium protocols/AAD, seven-day relay, adult-private
  isolation, explicit conflicts and privacy/hosting/cloud restrictions.

## Evidence and approval trigger

See ../../product/STAGE-5-GAP-ANALYSIS.md. Current membership roles are only
owner/guardian; require_owner protects invitations/removal. CalendarRepository
loads households LIMIT 1 and enrollment refuses an existing local family.
Household calendar keys expose the entire household calendar, even if a child
profile is withheld. Device upload sequence is global on the server but local
state is per family. Simply adding role strings or a household selector is unsafe.
ENGINEERING-STANDARDS requires approval if an accepted ADR must change.

## 1. Account identity and context authorization

Keep opaque UUID adult identity and contact-free, role-neutral registration.
Use account-<UUID> instead of a parent-specific authenticator label; do not demand
real name/contact details or infer a role from registration. Duplicate credential
IDs and ceremony replay fail safely; do not claim to deduplicate real people
without identity information. Reusing a request cannot create a second account.

Introduce typed authorization contexts: household, classroom, activity, school.
Scoped role assignments bind adult, context, status, optional expiry and an ACL
revision; resource grants remain explicit and context-bound. Household roles:
administrator, guardian, limited caregiver. Education roles: teacher, parent
volunteer, classroom administrator, school administrator, school-calendar
subscriber, with exact context/resource scope. Roles compose only inside their
assigned context. A school role never grants household/child/private access.
Scope relationships are validated explicitly, not inferred from matching names.

Effective authorization requires active session/device, live context membership,
allowed action for its scoped role, current resource grant, matching resource
context and any expiry/private-author rule. Deny unknown roles/actions. Private
calendar ownership overrides every administrative role. These are application
roles, not verification of legal guardianship or employment at a real school.
Stage 5 implements role/access infrastructure and management; it does not imply
Stage 6 classroom/social/product functionality is authorized.

Migrate existing owners to household administrators and materialize their existing
non-private resource authority. Preserve guardian grants unchanged. New admin
promotion is explicit; it cannot silently broaden child or private decryption.
Administrative permission management and actual key possession remain separate;
no device fabricates a missing established resource key.

## 2. Multiple administrators and scoped enrollment

Reuse hashed expiring one-use invites, QR/share/copy, pending state, device-code
comparison, full fingerprint pinning and signed resource-key handoff. Invitation
approval requires a current context administrator with authority over every
requested grant; ordinary guardians cannot promote themselves. Granting another
administrator, changing child grants and removing members require step-up below.

Lock the context and relevant membership/resource rows consistently. Administrator
removal/demotion, self-leave and account deletion cannot leave a live household
without an administrator: atomically require a remaining active admin, explicit
transfer, or separate confirmed household closure. Concurrent removals must not
both pass. A caregiver/expired/pending member never counts as remaining admin.
Keep unrelated context memberships, sessions and keys intact on scoped removal.

## 3. Multiple households and child representation

Keep one SQLCipher store, with explicit selected context in repositories,
controllers, queries, writes, conflicts, reminders, preferences and sync. Replace
LIMIT 1 assumptions; switching cancels/revalidates stale editors and async work.
Maintain context-specific relay cursors and one device-wide upload sequence and
scheduler across contexts, matching current server sequence semantics. Preserve
accepted/pending envelope bytes; cutover must reconcile pending work without
renumbering signed/authenticated operations or silently discarding intent.

Represent the same child in different households through separately authorized,
household-scoped child profiles/resources with independent opaque IDs and keys.
Optional correspondence lives only in encrypted authorized-device state after
explicit consent; no global plaintext child directory or automatically shared
key. Each household approves its own membership/grants. No cross-household data
copy, event synchronization or permission inheritance occurs implicitly.

Scope personal resources/backups by adult and context. Export snapshots sanitize
to exactly one requested household or the author's allowed private scope. A
multi-household live database is never uploaded whole. Restore into a missing
context stages a validated snapshot and atomically imports only that scope,
preserving other contexts and their unsent work; fail without partial activation.
Retain v2 outer cryptography; version scoped manifests/local schema as necessary.
Current authority and ADR-040 review still gate publication/cleanup after restore.

## 4. Child-limited caregiver encryption

Child profile read permission alone cannot restrict a shared calendar key.
Limited caregivers receive neither household calendar nor whole-family profile/
backup keys. Use independent child/caregiver-scoped calendar resources with
explicit guardian-reviewed scheduling copies and allowed profile resources.
Copies contain only the approved child's identity and approved scheduling fields;
exclude other children/adults, private mappings, unrelated notes and household
history. Parent reviews disclosure, including names accidentally present in titles.
Default caregiver calendar access is read-only and may expire. Do not silently
project every family event or allow caregiver edits to overwrite the source.
Reuse current libsodium AEAD/sealed grants and explicit conflict semantics.

Expiry/removal/narrowing revokes server permission and advances only affected
resource epochs before future publication. Every operation rechecks expiry and
ACL revision; scheduled maintenance is not the sole enforcement. Remaining
active authorized devices establish fresh epoch keys through the existing
serialized signed self-grant protocol. Previously downloaded copies remain.

## 5. Recovery and replacement

Reuse BIP-39, independent snapshot keys, protected activation, current-device
binding and old-device revocation. Offer optional recovery setup during progressive
onboarding; skip is visible and does not block calendar use. If enabled, require
phrase confirmation (re-enter randomly selected words) before backup creation.
Keep phrase display/transient state off server/storage/logs; interruption requires
fresh setup rather than persisting an unconfirmed secret.

Guardian-assisted recovery restores permitted family access only: recipient
strongly authenticates an active device, admin verifies the current fingerprint,
approves exact resources, then an existing authorized device sends scoped signed
sealed keys and current encrypted state. If the old passkey is unavailable,
register a new opaque adult and explicitly enroll it; do not impersonate/recover
the old account identity or private resources through guardian approval. No
family snapshot/private key/phrase is given to a limited recipient. If no
appropriate authorized key holder or user-owned snapshot remains, report that
content is unrecoverable; no server-held master recovery key is introduced.

## 6. Sensitive action safeguards and audit

Add operation-bound WebAuthn step-up using existing verifier/platform adapter.
Single-use five-minute challenges/proofs bind current adult/device/session,
action, context, intended target and expected ACL revision. Proofs are hashed
at rest and never placed in URLs. Recheck permissions under transaction locks;
stale/replayed/changed target/device/ACL proofs fail. Step-up verifies the current
phone and does not call the replacement flow or create/revoke device identity.

Require explicit impact preview, step-up and current authority for admin removal/
promotion, child-guardianship grants, membership revocation, household closure,
account deletion, authorized export and recoverable event restore. Exports are
local, explicit and limited to readable resources; default encrypted export.
Never export another adult's private resources or ungranted household/child data.
Any plaintext export must have a separate explicit boundary decision/disclosure;
it is not introduced by this proposal.

Use a separately permissioned encrypted audit resource for important actions.
Transactionally commit authoritative bounded operational action metadata/ACL
revision and a validated client-encrypted audit record with the action. Detailed
names/content live only in ciphertext; server retains no audit decryption key.
Client audit narration is untrusted and is not represented as server-verified
plaintext truth. Verify it against authoritative action metadata on display.
Approved detailed audit retention is 30 days, with closure/purge taking precedence;
opaque causal/security receipts may remain only as explicitly documented minimal
replay/idempotency state. Administrator audit access excludes adult-private details.
A missing audit envelope must not silently bypass the required action audit.

## 7. Closure, account deletion and 30-day event recovery

Account deletion removes credentials/sessions/devices, own personal resources/
snapshots and usage metadata, then removes its context memberships and rotates
affected shared keys. Preserve other members' context data and memberships.
Resolve last-admin status by explicit transfer/closure before destructive action.
Household closure revokes that context, purges its server grants/relay/email/
backups/audit content and queues authorized local cleanup; other contexts remain.
Access denial is immediate on transaction commit. Bounded application purge work
is idempotent, retryable and completes within a approved 24-hour application
purge target; provider backup retention remains a deployment-specific gap.
Offline devices cannot be guaranteed immediately erased. Destroy relevant local
keys/cache on authenticated reconciliation, not unrelated household/device keys.

Manual event deletion may retain an encrypted, resource-scoped recoverable copy
for at most 30 days. This is a new requested policy, not a previously located
accepted ADR. Expiry is the earlier of the restore deadline or applicable
retention/hard-delete requirement. ADR-039 retention deletion remains hard content
removal: no hidden 30-day extension of the default one-week policy. Account/
household closure and explicit permanent deletion purge recoverable copies.
Restore is a new explicitly reviewed authorized causal operation at current
epoch; replay/stale snapshots cannot resurrect hard-deleted content. Show actual
expiry/availability. Seven-day server relay is unchanged; a new phone cannot
recover 30-day history without an appropriate authorized encrypted snapshot.
Old external exports/provider copies cannot be promised erased retroactively.

## Implementation order and verification

After approval, implement compatible milestones with migrations/tests/docs:
contact-free identity and step-up; scoped roles/multi-admin; multi-context mobile
state/global sequence; child/caregiver isolation; scoped assisted recovery;
sensitive actions/audit/export/deletion/restore; full regression/acceptance.
Existing APIs and merged migrations stay intact; add new migrations and generated
OpenAPI updates. Old-client compatibility must fail safely when new scopes or
resource kinds cannot be understood; coordinated beta upgrade under ADR-030.
No new service/library/primitive is selected; reassess concrete dependency needs
before adoption. Hosting/cloud activation stays deferred. Stage 6 is not authorized.

Traceability: ../../testing/STAGE-5-TEST-PLAN.md maps all 17 mandated cases to
existing evidence and planned implementation tests. Baseline passes do not prove
new Stage 5 capabilities. The maintainer approved this design on 2026-10-16;
any later material departure must be reviewed separately.
