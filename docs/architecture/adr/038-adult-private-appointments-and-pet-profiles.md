# ADR-038: Adult private appointments and pet profiles

- Status: Accepted by maintainer on 2026-10-13
- Date: 2026-10-13
- Requested scope: Adult appointments, explicit household sharing, pet appointments,
  and selectable pastel profile colours.
- Supersedes: ADR-022 owner access to every resource; extends
  ADR-020 resource types, ADR-021 synchronization routing and ADR-032 for the
  new adult-specific backup path only. Implemented; executed verification is
  recorded in ../../testing/ADR-038-VERIFICATION.md.

## Problem

The current family calendar uses a household resource/key. An adult-private
appointment must never be written into that shared resource. UI filtering cannot
supply privacy. The household owner currently administers every resource; this
must change for adult-private resources. Existing owner backups and initial
hand-offs must not accidentally export another adult's private content.

## Proposed decision

1. Each authenticated adult owns a personal calendar resource. Only that adult's
   active device receives its key by default. Household ownership does not grant
   access, grant authority, or recovery access to another adult's personal resource.
   Offline drafts can be saved locally but cannot publish until identity/resource
   authorization is established; display this state explicitly.
2. New adult appointments default to Private. Explicit Share with household
   publishes a separately encrypted shared copy into the existing household
   calendar. Explain that all calendar-authorized guardians can then read it.
   Sharing requires preview/confirmation, including any pickup assignment.
   This proposal does not add arbitrary recipient subsets.
3. A local private-to-shared mapping connects the copies; IDs of private resources
   never enter shared payloads. Owner-confirmed updates queue both versions
   atomically in SQLCipher. Shared-copy edits from other guardians are preserved
   as explicit conflicts for the adult; they cannot overwrite private content.
   Unsharing tombstones the shared copy; recipients may retain previously seen
   details. Do not promise retrospective erasure. Shared-to-private conversion
   cannot turn an already disclosed event into a never-disclosed event.
4. Reuse libsodium encryption, signed recipient-bound key grants, current-device
   checks, epochs and replay protections. Server policy must enforce personal
   resource ownership independently from household role on every route, grant,
   relay, invitation, deletion, rotation and restore path.
5. An owner's family snapshot excludes other adults' private calendars, keys,
   outbox operations and private-to-shared mappings. An adult's private recovery
   requires their own recovery material and an adult-authorized encrypted snapshot;
   extend and version the backup contract before shipping private appointments.
   Successful login alone cannot decrypt private recovery data.
6. Pets are non-authenticating household profiles. Household events can reference
   adult, child or pet profile IDs through a typed participant model. Existing child
   assignments migrate losslessly. Pickup assignment remains a guardian reference.
7. Each profile offers named pastel choices with legible foreground text and
   names/icons alongside colour. Preserve stored colours on upgrade; changing
   a colour is explicit and synchronizes through the relevant encrypted profile.
   Profile sharing does not imply appointment sharing.
8. Notifications and push carry no private details. Adult-private events never
   enter household email suggestions, initial guardian hand-off, family export,
   cloud prompts, server logs or telemetry by default. Optional AI disclosure
   remains governed separately by ADR-036.

## Required implementation and acceptance

Update permission matrix, OpenAPI, PostgreSQL/local schemas, migrations, resource
catalog, sync dispatch, backup formats, profile editor, event editor and calendar.
Use prepared fixtures with stable scenario IDs for these journeys:

- ADULT-PRIVATE-001: private offline save and reconnect remain readable only by
  the author, including against the family owner and a cross-family attacker.
- ADULT-SHARE-001: adult confirms eye-exam sharing and pickup; authorized spouse
  receives the shared copy; private mapping/content never leaks.
- ADULT-SEC-001: owner cannot fetch/grant/rotate/restore another adult's private
  resources; revoked/replaced devices cannot receive future keys; replay rejected.
- ADULT-CONFLICT-001: duplicate retries, independent shared edits, unshare and
  concurrent changes preserve alternatives without silent overwrites.
- ADULT-RECOVERY-001: family backup excludes others' private content; adult-specific
  recovery works only with correct recovery material; corruption fails safely.
- PROFILE-COLOUR-001: adult/child/pet pastel choice persists across restart/sync,
  existing colours survive migrations and contrast/labels remain usable.
- PET-CAL-001: prepared pet profile creates, edits and syncs a household appointment.

The maintainer explicitly approved this security/backup extension and requested
product scope on 2026-10-13. No privacy claim is made until implementation and
required verification complete.

## Implemented recovery detail

The outer SART v2 AEAD format and derivation are unchanged. Local schema 7 adds
an authenticated `backup-scope-v1` marker (`family` or `adult:<account UUID>`).
Personal snapshots retain authorized historical resource keys, event vectors and
applied-operation IDs to decrypt earlier relay messages and preserve unsynced
edits. They never restore device private keys, sessions, old outbox envelopes or
device sequences. Current server epochs/directory authorization govern future
writes and grants. This extends ADR-032 only for personal snapshots; family
recovery keeps ADR-032's key/state clearing behavior. Local access begins
conservatively read-only for household resources until authoritative refresh.

Family snapshots remove private event rows, keys, conflicts, operations, resource
catalog entries and mappings before encryption. Secure-delete and VACUUM remove
deleted pages from the SQLCipher snapshot. Existing profile colours are preserved
by migrations; child colour edits gain durable causal vectors.

Each newly exported SQLCipher snapshot uses a fresh independent database key.
The v2 envelope wraps that snapshot key, never the live phone database key. A
family backup phrase therefore cannot unlock a separately acquired live phone
DB containing private appointments. Snapshot keys are erased from temporary
buffers after packaging; source DB encryption is unchanged.
