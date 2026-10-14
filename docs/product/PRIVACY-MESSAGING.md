# Privacy messaging — pamphlets, website, stores and in-app copy

Approved direction: 2026-10-13, ADR-036. Match claims to the deployed build and
verified provider configuration. This file is the source for future pamphlets;
no separate pamphlet or marketing website currently exists in this repository.

## Suggested short copy

“Calendar sync and backups are encrypted before leaving an authorized device.
Native AI processes suggestions on-device. If you choose optional cloud AI,
limited scheduling information may be temporarily processed by Sarti servers
and sent to Google Gemini with temporary
labels. This reduces exposure but does not make it anonymous. Email processing
has a separate plaintext boundary.”

For the current build add: “The optional broker is disabled by default and live provider testing is pending.
Local parsing and supported native AI remain the primary path.”

## Required distinctions

- Encryption protects local storage, synchronization and backups. It does not
  make an optional cloud inference request invisible to its recipient.
- Fresh per-request labels replace known people/places. Stored aliases, profile
  IDs, account IDs and the reverse mapping are excluded from the model payload.
- Conservative supported-token filtering blocks other text; this is not a
  universal detector for personal information. Schedules and even supported
  words may still identify people or reveal sensitive circumstances.
- Provider credentials, IP/network metadata and distinctive schedules may link
  requests despite changing labels. Never promise anonymity or untraceability.
- Cloud assist requires explicit current-version consent and provider
  configuration. Consent can be revoked; local parsing remains available. There
  is no silent native-to-cloud fallback and suggestions require approval.
- Ordinary inbound email is plaintext at the external gateway and during Sarti
  request processing before device-specific encryption. Persistent Sarti family
  content is encrypted; saying Sarti can never process plaintext is incorrect.
- Production provider retention/training terms, child-data eligibility, regions,
  legal review and physical-device guarantees remain release checks. Do not make
  zero-retention, no-training, legal-compliance or hardware-security claims
  without evidence for the deployed configuration.

## Do not use

- “Personal information never leaves your phone.”
- “No child data is ever sent to a server.”
- “Sarti can never read any family information.”
- “Random IDs make your data anonymous / impossible to identify.”
- “Everything is end-to-end encrypted” without specifying the flow and exceptions.

Review privacy policy, app/store notices and marketing together whenever a
provider or data flow changes. Do not advertise unfinished cloud functionality.
