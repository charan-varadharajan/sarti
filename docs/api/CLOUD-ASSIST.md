# Optional cloud assist API — ADR-037 / BUG-005

The primary Sarti path is supported native on-device AI plus deterministic local
parsing. This API is optional and default disabled; no automatic fallback.
Live testing was explicitly deferred by the maintainer on 2026-10-14.

- `GET /v1/ai/capability`: active-device authentication, `{available,consent_version}`.
- `POST /v1/ai/proposals`: active-device authentication; exact body
  `{version:1,consent_version:3,tokens:[...]}`. Unknown fields/raw text/unsupported
  words/IDs fail with 422. Maximum 100 tokens, each a grammar word, bounded clock
  or fresh UUIDv4 child/guardian/place label. Phone and server share the ADR-036
  vocabulary; only the phone holds reverse mappings.
- Response fields: optional bounded `timeHour`, `timeMinute`, `recurrence`
  (daily/weekly), `recurrenceWeekday`; extra fields fail closed. Phone additionally
  requires explicit source evidence and preserves known/local/user-edited values.
- 401 stale/revoked/missing device; 429 caps; 503 disabled/provider failure.
  All route responses, including errors, are no-store. Errors never echo content.
  OpenAPI is generated and contract-tested.

The Sarti server temporarily sees scheduling tokens. This is a plaintext
processing boundary separate from encrypted sync/backup, even with temporary
labels. No prompt/response/hash/cache/job/body logs persist. Runtime provider
secret stays on the server and is sent only as a provider header. Fixed REST
host/model policy, no redirects/tools/grounding/files/retries, ten-second total
deadline, 16 KiB streamed response limit, disabled thinking and 256 output tokens.

Before I/O a PostgreSQL transaction reserves adult/day (10) and global/month
(1,000) attempt counts across replicas. Failed attempts count; no automatic
retry. This is a usage bound, not an invoice guarantee. No app/account/family/
device/request IDs enter the provider payload. Counts contain only scope/date/
count/expiry; no family rows exist. Adult deletion purges its counters; global
aggregate remains until expiry. Expiry purge runs on reservations and daily
`python -m sarti_backend.ai.purge` maintenance.

Operator activation requires existing billing-backed project verification,
provider/audience/region/privacy review, current model support and price review,
runtime secret, `SARTI_CLOUD_AI_MODEL=gemini-2.5-flash-lite`, separate reviewed and
enabled flags, daily purge scheduling, infrastructure logging/body-retention
review and a live synthetic smoke check. Flags/keys are not independent evidence
of billing eligibility. No billing, deployment or real family request is enabled
by this implementation. Local Docker remains disabled; do not add mobile keys.

Primary references reviewed 2026-10-14: [REST](https://ai.google.dev/api/generate-content),
[model](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite),
[terms](https://ai.google.dev/gemini-api/terms). Recheck before activation.

Provider compatibility limit: Google's current model documentation restricts
Gemini 2.5 access to projects/users with prior usage. The implemented 2.5 adapter
therefore is not a ready-to-activate choice for a new project. Before any cloud
activation, review an eligible current model/adapter and perform the separately
authorized live synthetic check. Native/local use is unaffected.
Source: [Gemini 2.5 Flash-Lite access notice](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite).
