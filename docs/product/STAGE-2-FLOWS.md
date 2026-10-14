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
- **Act:** One Event button opens the create/edit surface. Save commits locally
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
