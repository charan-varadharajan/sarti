# ADR-039: Family-managed mobile calendar retention

- Status: Accepted by maintainer on 2026-10-13; implemented; final checks pass in ADR-039 verification report
- Date: 2026-10-13
- Requested scope: Family account admins configure mobile calendar-entry
  retention: **1 week (default)**, **1 month**, **3 months**, **1 year**, **Never**.
  Preserve future appointments and active recurring series.
- Supersedes: ADR-022's content-bearing event tombstone representation
  for retention deletion. Other accepted security/backup decisions remain intact.

## Family setting, mobile effect

There is one policy per family account, not one independently chosen by each
phone. Changes propagate to authorized family devices and cleanup affects mobile
calendar history. This does not alter the server's seven-day encrypted relay TTL,
user-controlled encrypted backup lifetime or email retention. Sarti stores
ciphertext and operational metadata; it must not claim the server stores no data.

Use existing family/calendar administrator authority: the owner or a guardian
explicitly granted `admin` on that family's household calendar. `write` permission
alone does not allow policy changes. The existing single-owner family model is
unchanged; granting calendar administration is not promotion to another owner.
The API must independently authorize policy changes, including stale/revoked
access and cross-family attempts. Persist only the bounded policy enum/revision
as family configuration metadata, not calendar content or deletion targets.
Version/revision checks reject concurrent stale policy changes for explicit review.
Devices cache the last authenticated policy in SQLCipher; no raw family content
is needed on the server for mobile retention.

## Calendar behavior

- Settings → Calendar retention shows the five options, the shared family scope,
  current value and deletion preview. Ordinary members can view but not change it.
- One week is the default for new families. Existing families preview affected
  history before an admin activates the default; app upgrade alone does not
  destroy existing history. Shortening a saved policy previews/confirmations once
  at the admin's policy change, not repeatedly on every receiving phone.
- Expiry runs from appointment end, not creation date. A week is seven elapsed
  days. Month/year thresholds use calendar subtraction in the event's IANA zone,
  clamping month-end/leap-day dates. Event end uses actual start plus elapsed
  duration under established DST semantics. Exact cutoff is eligible.
- Future/ongoing appointments remain. Preserve active/unbounded recurring series,
  including their full definitions. A finite series expires only after its last
  actual occurrence ends and ages past the selected period. Unknown completion
  or recurrence iteration limits retain data instead of guessing.
- Apply the family period to each adult's private entries on that adult's own
  device as well; the policy grants admins no private keys, inspection rights or
  authority to issue another adult's private deletions. No separate per-phone
  or per-adult retention choice is introduced.
- An authorized calendar admin originates normal shared deletion operations;
  other phones apply them through authenticated encrypted sync. An adult's own
  phone handles private deletion. Read-only recipients cannot originate shared
  writes. Unknown/revoked authority defers automated writes. A phone offline from
  a policy change uses only its last authenticated policy until catch-up; do not
  claim immediate cleanup on disconnected devices.
- Run bounded cleanup on unlocked startup, foreground resume and authenticated
  catch-up. Revalidate current policy, authority, event vector and eligibility
  transactionally before mutation. Do not promise precise OS background timing.
- Pending edits, open conflicts and independently changed shared copies defer
  cleanup. Concurrent edit versus deletion preserves alternatives for explicit
  resolution; retention cannot bypass ADR-038's shared-copy review.
- Never stops future cleanup and cannot undo completed deletions. Cancel local
  reminders for removed entries. Duplicate retries/interruption remain safe.

## Actual deletion versus hiding

The existing `deleted=true` event still contains its title/notes/participants.
Retention must instead remove content and related rows, retaining a minimal
versioned deletion record with event/resource identity and causal state needed
for safe synchronization. Introduce a dedicated deletion representation rather
than fake titles/times to satisfy CalendarEvent. Local removal and outbox commit
atomically. Old pending encrypted envelopes are not rewritten or discarded;
operational content needed by pending writes/conflicts is deferred and disclosed.
Prune obsolete uploaded content only when no pending/conflict dependency needs it.
Do not erase replay/causal bookkeeping merely because relay TTL elapsed. Replay,
reorder, equal/stale operations must not resurrect removed history; newer edits
must still undergo the established causal/conflict checks.

## Backups and existing defects

Existing immutable exports/hosted snapshots can contain older calendar history.
This policy does not delete or replace them, alter backup encryption, or change
family recovery rules. Clearly disclose those copies. After explicit restore,
normal policy adoption/catch-up safeguards apply before cleanup; restored content
must not be destroyed during staging. BUG-022 remains a separately documented
family-recovery continuation blocker, not silently fixed or claimed resolved by
this feature. Defer automatic cleanup on an unvalidated restored family until
safe continuation is established. This limit must appear in the completion report.

## Implementation and tests

Implement the family preference API with current admin checks and optimistic
concurrency; mobile cache/settings/preview; eligibility evaluator; minimal
sync deletion/local migration; reminders; encrypted sync integration. Generate
OpenAPI from FastAPI if contracts change and document schemas, permissions,
modules and privacy semantics together. No new external service, SDK or crypto
primitive is proposed.

Prepared RETENTION-* scenarios in TEST-SCENARIOS.md cover options/admin authority,
boundaries/DST/recurrence, two-family isolation, private access, pending/conflict
preservation, retries/replay, migrations and native UI. Run applicable suites,
inspect only failures, spot fix and rerun as requested. Physical OS/background
behavior and BUG-022 recovery remain explicit limitations.

## Approval and implementation

The maintainer confirmed one admin-managed family policy affecting mobile
calendar entries. The maintainer explicitly approved ADR-039 on 2026-10-13, authorizing the
change from content-bearing ADR-022 tombstones to minimized deletion records.
Implementation uses PostgreSQL migration 0009/local SQLCipher v8 and beta
version 0.3.0+3. Results and limits are recorded in
../../testing/ADR-039-VERIFICATION.md. Pending edits/conflicts defer cleanup;
explicit Keep exempts that event version and synchronizes as `retention_kept`.
Changed event versions become eligible again. The exemption is stored with
`event_versions` causal state rather than resettable UI preferences, preserved
by personal recovery and sent in scoped guardian handoff. An unvalidated family-only restore
receives a local cleanup-pause marker; accepted family recovery semantics and
BUG-022 remain unchanged. An initial offline-only calendar needs service
connection before family policy management/automatic cleanup is available.

## Superseding recovery pause — ADR-040

Family restores remain paused until ADR-040 validates history, current authority
and available relay catch-up, resolves/reviews pending intent and conflicts, and
the owner explicitly reviews history and resumes cleanup. A policy refresh alone
cannot resume it. Incomplete legacy snapshots stay blocked/readable.
