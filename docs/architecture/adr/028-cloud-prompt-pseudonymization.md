# ADR-028: Local cloud-prompt pseudonymization

- Status: Accepted
- Date: 2026-10-11
- Supersedes: ADR-023 cloud-assist rules 1 and 2

## Context

The product owner approved optional cloud AI in ADR-023, then approved replacing
children's names with locally managed aliases before a request leaves the device.
A first name without an account identifier may still contribute to identifying a
person when combined with a place, time, and repeated schedule. Sending the raw
sentence is therefore unnecessary exposure.

## Decision

Each local child profile has a cloud alias such as `happy-frog-4821`. Sarti
generates one with a cryptographically secure random source unless the parent
chooses one. A chosen alias must use 3-32 lowercase letters, numbers, or hyphens,
must differ from the child's display name, and must be unique within the local
household.

The child-to-alias relationship is stored only in the SQLCipher database. Before
an optional Gemini call, the device replaces every locally known child display
name with its alias. Locations already identified by the deterministic parser,
plus locations explicitly supplied by local application context, are replaced
with request-local `place-N` tokens. Returned structured fields are mapped back
on-device. IDs, profile records, keys, account data, and the reverse mapping are
never sent.

If the deterministic parser identifies a child token without a corresponding
local alias, cloud enrichment fails closed and returns the deterministic proposal.
The cloud response remains additive and cannot overwrite confidently parsed
fields. Event creation still requires an editable preview and explicit approval.

## Privacy limits

Pseudonymization is not anonymization. The provider still receives the activity,
date or recurrence, time, sentence structure, and any free-form detail that was
not recognized locally. A stable child alias also permits correlation between
requests from the same installation. The cloud feature therefore still requires
clear disclosure and explicit opt-in. Users must be able to use the deterministic
parser without enabling it.

## Consequences

- Schema version 4 adds `children.cloud_alias` and a case-insensitive unique
  index per household. Existing profiles receive random opaque aliases during
  migration.
- Parent-selected aliases improve recognition but are rejected when they copy a
  child's real name.
- Known venues no longer cross the boundary verbatim. Unrecognized sensitive
  text remains a documented residual risk until broader local entity detection
  exists.
