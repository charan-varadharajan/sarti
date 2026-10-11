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
- Private content is not sent to a cloud model.
- Removing a device prevents future access but cannot erase data already copied
  to that device.

## Acceptance boundary

Detailed stories and measurable acceptance criteria must be added before the
corresponding feature is implemented. Adding a deferred capability requires
explicit approval and a scope update.
