# P0 product scope

## Product promise

Sarti reduces the effort of organizing a family while keeping sensitive family
information encrypted on authorized devices. It provides AI-assisted daily and
weekly planning with explicit confirmation before any generated change.

## Included capabilities

- Frictionless onboarding
- Family and guardian profiles
- Family calendar, recurring events, and colour-coded schedules
- Confirmed natural-language event entry
- Native on-device AI with a deterministic fallback
- Local notifications with no sensitive payload content
- SQLCipher-encrypted local storage
- Resource-scoped end-to-end encrypted family synchronization
- Offline use and deterministic conflict handling
- Email-to-calendar suggestions within the documented plaintext boundary
- User-owned encrypted backup and restore with recovery keys
- Basic pickup assignments

## Deferred capabilities

- External calendar synchronization
- Location-aware departure estimates
- Birthday invitations and RSVP workflows
- Advanced sensitive-information sharing
- Pickup verification codes
- Classrooms and activity groups
- Chores and rewards
- Grocery lists and meal planning
- Document vault

## Product invariants

- A generated suggestion is visibly distinct from saved family state.
- Saving an AI suggestion requires an explicit user action.
- Core calendar use remains available offline.
- Local/native AI has no cloud fallback. Optional cloud AI requires explicit
  consent and ADR-036 minimization; limited scheduling information may leave
  the device and is not guaranteed anonymous. Encrypted sync/backup guarantees
  do not cover this separate opt-in disclosure.
- Removing a device prevents future access but cannot erase data already copied
  to that device.

## Acceptance boundary

Detailed stories and measurable acceptance criteria must be added before the
corresponding feature is implemented. Adding a deferred capability requires
explicit approval and a scope update.

## Approved extension — ADR-038

2026-10-13: The maintainer requested adult appointments with deliberate household
sharing, pet appointments and selectable pastel profile colours. ADR-038 records
concrete behavior and the necessary private-resource/backup authorization change.
The maintainer explicitly approved ADR-038 on 2026-10-13. Adult private
resources, explicit household copies, pets and profile colours are implemented;
see ADULT-AND-PET-APPOINTMENTS.md and the verification report. This is a specific
authorized P0 extension, not general approval for Stage 4 or other deferred work.
