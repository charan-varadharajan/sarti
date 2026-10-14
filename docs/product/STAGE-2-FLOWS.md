# Stage 2 interaction flows

## First use

1. Unlock device secrets with the platform user-presence check.
2. Register a passkey when server synchronization is enabled.
3. Tap **Create family**; the calendar opens immediately.
4. Add children later from the calendar. Each child has a distinct ARGB colour.

## OPEN → SEE → ACT

- **Open:** Sarti opens directly to the calendar after local unlock.
- **See:** Today, Week, and Month are one segmented control; events show time,
  child colour, recurrence, and pickup state.
- **Act:** One Event button offers Enter event details or Describe an event. Save commits locally
  with reminders and an encrypted outbox row in one operation.

Guardians can cancel or delete an event from its row. Weekly recurrence previews
retain local wall time across daylight-saving transitions. When two offline edits
are concurrent, a badge opens both versions and requires an explicit choice.

## Guardian invitation

An owner creates a 48-hour one-use invitation and sends the token out of band.
Acceptance remains pending. The owner reviews resource permissions and approves;
an authorized device then sends signed sealed resource-key grants. Revocation
stops future relay/key access and rotates epochs.

## Recovered family calendar (ADR-040)

After replacement restore, the calendar stays readable with **Review recovery**.
That card checks access and available updates, shows snapshot time and the
seven-day relay limitation, then offers individual recovered-change approval and
conflict choices. New profile sharing starts unchecked. A separate **Review
history and resume cleanup** dialog previews current policy candidates; Cancel
keeps editing/cleanup paused. Changed policy/history invalidates approval. Legacy
missing history gives guidance for a complete authorized snapshot.

The Family menu now opens one hub for family/guardian display names, children,
People/Pets profiles, invitations/removal and retention. Offline/unconfigured guardian
management is explained instead of bypassed. Multiple natural-language events
receive separate editable previews; Review next writes nothing and final Add N
commits the reviewed batch. Explicit durations/end times are honored or require
clarification; unspecified duration visibly defaults to one hour. Undo lasts
five seconds (OS accessibility behavior respected) and opens an editor with
explicit Delete, Cancel and dirty/valid Save; it does not immediately mutate.

## Profile and entry refinement — BUG-023

More lists Family, People, Pets and Calendar retention separately. People has
own adult profile, Add adult (secure invitation), Add child, adults and children;
Pets has only pet profiles and Add pet for admins. Choose color labels avoid
palette terminology. Missing guardian connection is actionable guidance;
a configured expired session offers sign-in rather than a dead control.

Blank child aliases are generated automatically and uniquely within the local
family. They remain encrypted compatibility profile data, not anonymity or the
cloud security boundary; cloud scheduling uses fresh request-scoped labels.

Manual and natural-language review both use Hours and Minutes (0–59); unspecified
duration still defaults visibly to one hour. Total elapsed duration must be
1 minute through 7 days. Ends uses local 12/24-hour preferences; include a date
across midnight and zone when elapsed duration crosses a DST offset. Existing
stored minutes, recurrence, timezone and explicit approval semantics are unchanged.
Describe remains local/native with deterministic fallback; no cloud auto-call.
