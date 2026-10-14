# ADR-037: Server-managed optional cloud assist

- Status: Accepted — maintainer approved implementation 2026-10-14
- Date: 2026-10-13
- Scope: Remaining BUG-005 credential/shipping integration
- Extends: ADR-036; adds an explicitly disclosed Sarti plaintext processing boundary
- Does not authorize: Deployment, billing activation, production data transmission

## Verified constraint

Google's Gemini API terms, effective March 23, 2026 and reviewed 2026-10-13,
prohibit sensitive/confidential/personal information on unpaid services. Billing-
backed API projects qualify as paid services. Paid-service prompts/responses
are not used to improve Google's products, but limited abuse-monitoring logging
still applies. Fresh labels do not establish that schedules are non-personal.
This design therefore excludes unpaid-service processing of real family input.
Provider age/audience, region and processing eligibility must also be reviewed
for the adult-guardian app before release. Paid service is not a zero-retention
or general compliance guarantee.

Sources: [Terms](https://ai.google.dev/gemini-api/terms),
[Retention](https://ai.google.dev/gemini-api/docs/zdr),
[Key handling](https://ai.google.dev/gemini-api/docs/api-key),
[Model lifecycle](https://ai.google.dev/gemini-api/docs/deprecations).

## Architecture

1. Phone locally prepares ADR-036's bounded token payload and fresh labels.
   Unsupported input never reaches the broker. A separate explicit “Use cloud
   assist” action is available only with current consent, signed-in active device
   and configured server capability. Native failure never triggers it silently.
2. `POST /v1/ai/proposals` authenticates the current device. It independently
   validates exact version/token schema and rejects arbitrary text/extra fields.
   No family resource ID or raw sentence is needed in the request body.
3. Sarti processes those scheduling tokens in memory and calls a fixed provider
   endpoint/model with a fixed instruction. Client values cannot select a URL,
   model, provider credentials or tools. No prompt/response persistence, job,
   retry queue, cache, tracing body or content logging is introduced.
4. Credentials stay in server runtime secrets under least privilege, never the
   Flutter bundle, response, logs, Git or caller-supplied URLs. Use the existing
   pinned HTTPX dependency for the provider REST adapter; remove direct mobile
   Gemini credential dependence when shipping integration is complete.
5. No Sarti adult/device/family/session/request IDs are forwarded to Gemini.
   Sarti still knows the authenticated caller and temporarily sees scheduling
   tokens; this is outside ciphertext-only sync and is not end-to-end encrypted
   against Sarti or the model provider. Gemini sees Sarti's provider/network
   metadata, not necessarily an anonymous request.
6. Both server and phone validate bounded time/recurrence-only output. The phone
   additionally checks source evidence and preserves local values. The proposal
   remains editable and requires explicit save; no API event mutation occurs.
7. Provider failure, timeout, quota, disabled capability or revoked consent leaves
   the local/native/manual flow available. Bounded errors never echo provider
   bodies, prompts, headers or secrets. Requests/responses use no-store headers.

## Activation and abuse controls

Default disabled. Enabling requires an explicitly selected supported model,
verified billing-backed project, runtime secret, approved provider/audience/region
review and deployment-specific retention/logging review. The server cannot infer
paid-service eligibility from the mere presence of a key. Operator verification
is required; do not advertise a configuration flag as independent proof.
The legacy hardcoded mobile model is not evidence of current compatibility.

Proposed initial caps: **10 attempts per adult per UTC day, 1,000 attempts total
per UTC month**, counting reserved attempts before external calls, including
failed/time-out calls. A PostgreSQL transaction atomically reserves both counters
across replicas. No automatic provider retry; 10-second deadline, bounded input
and at most 256 output tokens including model thinking where supported. A kill
switch stops new calls. Counts persist without prompt/token/hash content; rows
expire after 35 days. New metadata migration and tests are required. Any family/
account deletion implementation must include associated usage metadata purge.

The caps are proposed usage limits, not an exact currency/invoice guarantee.
Model prices, input-token bounds, provider project quotas and billing alerts must
be verified before activation. Hosting/database and requests from other clients
are outside this app counter. No billing account or paid resource is activated by
approval to implement disabled code; live activation remains a separate action.

## Disclosure changes

Consent version 3 would explicitly state: “Sarti's server and Google Gemini can
process limited scheduling information when you request cloud assistance. Known
people/places use temporary labels. Sarti does not save the prompts, but Google's
provider retention rules apply. Information may still be sensitive or identifying.”

Update privacy policy, README, public-copy guidance, architecture/trust/data-flow
and API/module docs together. Never extend the sync/backup E2EE claim to this
processing path. Earlier consent does not enable version 3 automatically.

## Required implementation verification

- Device/session rejection, revocation and no caller identity in provider payload.
- Client and server schema parity; raw/private/extra-field/injection rejection.
- Atomic multi-replica quota reservations, adult isolation, global cap, expiry,
  rollback, disabled capability and no duplicate provider calls from retries.
- Captured provider requests: fixed destination/model, secret confined to header,
  no log/error/URL/persistence leakage and no provider tools/grounding/file use.
- Response limits, timeouts, malformed/invented output and local fallback.
- Prepared UI: direct proposal entry, explicit cloud action, renewed consent,
  editable result and no calendar mutation before approval.
- Migration round-trip/data preservation, OpenAPI contract, full regressions and
  live synthetic-only smoke against the selected billing-backed project before
  any family-data activation. Mocks cannot close live provider acceptance.

## Approval and activation boundary

Maintainer explicitly approved ADR-037 implementation on 2026-10-14. The broker
is implemented disabled by default. Approval excludes billing activation,
production deployment and real family-data transmission. Live synthetic-only
provider acceptance still needs an eligible billing-backed project and reviewed
configuration; mocks do not close that gap.

Implementation selects the operator-configured `gemini-2.5-flash-lite` REST
adapter, with no default model, HTTPX 10-second total deadline, no redirects or
automatic retries, `store:false`, disabled thinking and a 256 output-token bound.
Model lifecycle/support, price and provider eligibility must be checked again
before activation. Official REST/model/terms were reviewed 2026-10-14:
https://ai.google.dev/api/generate-content,
https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite,
https://ai.google.dev/gemini-api/terms.

Migration 0010 adds only scope/date/count/expiry usage rows. A PostgreSQL
transaction lock serializes global/monthly and adult/daily reservations before
I/O. Failed attempts count. Adults' deletion triggers purge their rows; no
family identifier is stored in this table, so no family-scoped rows exist.
Expiry is purged on reservations and by a required daily maintenance command
(`python -m sarti_backend.ai.purge`); schedule that command before activation.
Sarti persists no prompt, response, content hash or provider request record.

Provider compatibility limit: Google's current model documentation restricts
Gemini 2.5 access to projects/users with prior usage. The implemented 2.5 adapter
therefore is not a ready-to-activate choice for a new project. Before any cloud
activation, review an eligible current model/adapter and perform the separately
authorized live synthetic check. Native/local use is unaffected.
Source: [Gemini 2.5 Flash-Lite access notice](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite).
