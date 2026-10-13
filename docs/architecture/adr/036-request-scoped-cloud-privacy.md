# ADR-036: Request-scoped identifiers and minimized cloud input

- Status: Accepted
- Date: 2026-10-13
- Authorization: Maintainer approved fresh identifiers, omission of requester IDs,
  minimized structured fields, fail-closed submission and accurate public claims.
- Supersedes: ADR-028 transmission of stable child aliases and free-form text;
  ADR-023 raw-text cloud input. Other consent/additive/confirmation rules remain.

## Decision

Optional cloud requests use fresh cryptographically random child, guardian and
place labels generated for each invocation. Repeated references within that
invocation use one label. No application requester/account/family/device ID,
stored child alias or reverse mapping enters the model payload. The mapping is
held only in the request object in memory and is not persisted or logged.
Existing SQLCipher aliases are retained for compatibility; no migration or
silent recolouring/profile rewrite is needed.

Replace recognized local people and places in one pass, then tokenize a bounded
English scheduling grammar. Submit a versioned JSON token array, never the raw
sentence, arbitrary titles, notes, email bodies or database context. Unknown
words, unsupported characters/numbers, ambiguous entity mappings or oversized
input block submission and return the local proposal. The vocabulary is a
conservative product allowlist, not a general PII detector; supported words may
still reveal sensitive circumstances. This deliberately limits cloud utility.

Cloud output is untrusted: only time/recurrence fields are accepted, with values
supported by explicit source tokens. Names, titles, addresses and arbitrary
output fields cannot enrich a proposal. Local/native parsing remains available,
there is no automatic cloud fallback, and saving still requires user approval.
Consent disclosure version 2 defaults off and does not inherit version 1 opt-in.

## Honest disclosure

Describe synchronization/backup encryption separately from cloud AI and email.
Cloud AI may disclose scheduling information even with fresh labels. Labels do
not make data anonymous, guarantee removal of every identifier or prevent
correlation from schedules, network metadata or provider credentials. No requester
ID in the model payload is not a promise of anonymous network access. Provider
retention, training, eligibility and legal basis must be verified for the chosen
production service; no zero-retention promise is made here.

Approved short copy: “Calendar sync and backups are encrypted before leaving
an authorized device. Native AI processes suggestions on-device. If you choose
optional cloud AI, limited scheduling information may be sent to Google Gemini
with temporary labels. This reduces exposure but does not make it anonymous.
Email processing has a separate plaintext boundary.”

## Boundaries and verification

This privacy change does not activate cloud inference or embed a reusable key.
BUG-005 credential delivery/shipping integration and live provider validation
remain open. A backend credential broker is not implemented by this ADR; its
processing boundary, abuse/cost controls and provider configuration still need
an implementation decision. No new dependency, backend endpoint or database
column is introduced.

Tests must capture the actual adapter payload without a live provider, prove
fresh/repeated identifiers, no stable alias/requester/profile/context leakage,
blocked unknown input with zero transport calls, strict/evidence-bound response,
local fallback, renewed consent and truthful UI copy. Mocks do not establish
provider retention, network anonymity or native inference compatibility.
