# Optional family setup — BUG-020

Implementation candidate; verification is pending while automated failures remain.
ADR-022 progressive onboarding and ADR-020/035 encrypted profile sharing apply.

1. Empty device: Create family opens Set up your family.
2. Family/display names are optional drafts, bounded to 120 characters. Back
   before Continue writes nothing. Continue explicitly creates the local family
   with entered trimmed names or the visible My family/Me defaults.
3. Skip setup creates the default usable family and opens the calendar directly.
4. After Continue, the optional children screen explains that each child is
   saved when Add is pressed. Back/Open calendar preserves those explicit saves;
   parents can finish with no children. There is no whole-form discard promise
   after family creation or an explicit child save.
5. Add child uses the shared creation form: required name, named colour choices,
   optional retained private alias and separate profile-sharing consent. Default
   colour is unused where available; after all six suggested colours are used,
   explicit colour reuse is required. Names remain alongside colours.
6. Profile sharing defaults off for each child. The existing encrypted child
   operation/provisioning path is reused, including the explicit sharing flag.
   The form pins its family identity and rechecks the current owner access cache
   before writing. Invalid aliases leave the draft open without profile writes;
   errors are bounded and are not logged or reflected as exception contents.

Names/colours/aliases stay in draft memory until their explicit save, then use
SQLCipher and existing resource-encrypted synchronization. Family provisioning
requests remain metadata-only. No API/schema/migration/provider change.

The same editor is used from the calendar Add child action to avoid duplicate
validation/sharing/colour implementations. This implements the new-child
creation portion associated with BUG-015 but does not resolve existing duplicate
colours, profile-edit synchronization or shared-event colour indicators.
BUG-021's general family-management hub/adult edit actions are separate.

Prepared scenarios are in TEST-SCENARIOS.md; current checks and limitations are
in `../testing/BUG-020-VERIFICATION.md`. Do not claim device/provider acceptance
from a mock or a build, and do not mark this journey verified until failures pass.
