# Adult and pet appointments — ADR-038

Approved by the maintainer on 2026-10-13. Implementation verification is tracked
in `../testing/ADR-038-VERIFICATION.md`; physical-device acceptance remains separate.

## Interaction

Calendar → Event → My private appointment → edit details → Save. Adult
appointments use a personal calendar resource and default to private. With an
own adult profile selected, a new event defaults to private automatically.
Existing shared events retain their sharing semantics; turning off a flag cannot
make a previously disclosed event undisclosed.

To request a spouse pickup: select the pickup guardian, enable Share with
household, review the disclosure and press Save and share. All guardians with
household-calendar access can read that distinct shared copy. Participant profile
sharing and appointment sharing are separate decisions. Unsharing tombstones the
copy and preserves the private event; earlier recipients may retain old details.

If another guardian changes the copy, saving fails without altering either
version. Review household copy displays its latest details. Use my preview
acknowledges that version; a subsequent Save and share replaces it. Another
intervening edit invalidates that acknowledgement and requires another review.
Cancel preserves existing records.

People, pets & private backup menu → People & pets → My adult profile or Add pet.
Saving a profile explicitly shares its name/colour with current calendar guardians.
Adults edit their own profile; family owners maintain pets and child colours.
Pets do not authenticate. In Event, select the pet profile for a household
appointment. Existing guardian invitation/removal remains under Family guardians.
This screen does not yet implement general family-name or guardian-name editing.

Named pastel choices: Blue, Green, Purple, Orange, Rose and Teal. Upgrades retain
existing colours; users explicitly choose replacements. Names and type labels
remain visible, and calendar avatar foreground adapts to luminance. Palette colours
are presentation data inside encrypted profiles, never authorization identifiers.

## Offline and recovery

An offline-only installation can create an encrypted local adult identity and
private drafts. Its private resource is not published until passkey authentication
binds that unpublished identity once. A different later account does not inherit
already-bound private appointments. Existing authenticated identities survive
session expiry in protected storage for offline use; server authorization still
rejects expired/revoked sessions.

My private backup uses the adult's own server snapshot and recovery phrase.
Family backup excludes all private calendars. A private snapshot can include the
adult's already-readable household state and their private state; it excludes
other adults' private resources. Use a separate recovery phrase and keep it safe.
Login permits retrieval, not decryption. An empty replacement installation can
choose a family or personal snapshot. Existing local data prevents replacement.

## Boundaries

Private resources remain associated with an active household membership; losing
membership can block server access. Revocation cannot erase earlier local copies.
The server learns opaque account/resource routing, epochs, sizes and request timing,
not titles, profile names, pickup text or keys. The native/optional-cloud AI paths
are unchanged; private-event selection does not authorize cloud disclosure.
Pet/adult natural-language parsing is not added by this editor change.

Calendar audience labels distinguish Private, Shared with household and Household.
Compact shared blocks use one primary resolved profile colour; all participant
names remain in labels/tooltips, with child avatars when space permits. Changing
colour is deliberate and does not create another profile or event.
