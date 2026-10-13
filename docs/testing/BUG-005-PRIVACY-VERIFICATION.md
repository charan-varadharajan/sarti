# BUG-005 privacy remediation — ADR-036

Date: 2026-10-13. Privacy controls implemented; shipping cloud integration and
live provider acceptance remain open. No Stage 4 work.

## Approval and delivered behavior

Maintainer approved fresh request labels, no unnecessary requester ID, minimized
structured input, fail-closed submission and careful public privacy wording.
ADR-036 supersedes ADR-028 stable-alias/free-form transmission rules. It does
not activate cloud inference or authorize an implemented backend broker.

- `prompt_pseudonymizer.dart`: one-pass known-entity substitution with secure
  random request labels; bounded supported English scheduling tokens; unknown
  input blocked; temporary reverse mapping; strict source-supported output.
- `gemini_ai_provider.dart`: captured transport seam, JSON token payload only,
  no stored alias/IDs/profile/raw-sentence export, time/recurrence-only schema,
  bounded response and silent local fallback without content logging.
- Consent store/dialog: disclosure v2 requires fresh opt-in; qualified text
  explains schedule sensitivity, network/provider correlation and limitations.
- Privacy policy, README and `product/PRIVACY-MESSAGING.md`: distinguish local
  storage/sync/backup encryption from native AI, cloud disclosure and plaintext
  email processing. No blanket “personal information never leaves your phone”
  or anonymity promise. AGENTS.md requires future public copy to follow guidance.
- Architecture/index/ADRs, P0 exception, security/threat model, module/local-DB
  docs, scenario catalog, bug/status/changelog updated together.

No backend endpoint, API specification, database schema/migration, dependency
or version change. Stored aliases remain encrypted for compatibility and are
excluded from cloud payloads. No request mapping is persisted.

## Automated checks

Initial analysis and Flutter commands failed before source-review corrections
were completed. Failure logs were not inspected. Review corrected missing
braces and consent-test scrolling; checks were rerun on the changed source.

| Check | Final result / ignored log |
| --- | --- |
| Dart formatting | PASS; bug005-format.log, final whole lib/test check bug005-format-final.log |
| Flutter analysis | PASS; bug005-analyze.log |
| Full Flutter unit/widget suite, including privacy/security | PASS: 140 passed, 2 opt-in host tests skipped; bug005-flutter.log |
| Final privacy/consent tests after extra revocation/no-write assertions | PASS; bug005-privacy-final.log |
| Backend Ruff format/lint, Mypy, Bandit | PASS; bug005-backend-check.log |
| Backend unit tests | PASS; bug005-backend-unit.log |
| Runtime dependency pip-audit | PASS; bug005-dependency.log |
| Version 0.1.0+1 | PASS; bug005-version.log |
| Python runner/version tooling tests | PASS; bug005-tooling.log |
| Existing local Docker service live/ready | PASS; bug005-health.log; no image rebuild |
| Staged offline secret scan / whitespace | PASS; bug005-secret-scan.log; cached pinned scanner with no network, no mounts, read-only container |

`CLOUD-PRIV-001..006` verify fresh/repeated labels, exact local mapping, Unicode
and boundaries, captured outgoing prompt, absence of stable/private identifiers,
zero calls for unsupported/private/injection input, strict grounded output,
provider-failure fallback and additive recurrence. Consent tests cover default
and reversible choice, v1 rejection, v2 gate and prepared direct Privacy & AI
screen with qualified copy. Latest widget assertions include revocation and no
calendar write. Tests use synthetic data and injected provider transport.

## Limits and checks not executed

- No live Gemini call or real user data sent. Credential delivery, shipping
  integration, existing SDK/model validity, provider terms/eligibility and live
  retention/training behavior remain BUG-005 acceptance work. No compatibility
  or anonymity claim follows from a mock transport.
- Native iOS/Android journeys/builds not rerun: no platform code, dependencies
  or native inference changes. Physical OS/storage/inference remains unverified.
- PostgreSQL/API integration/migration/HTTP contracts and backup portability not
  rerun: no backend, schema, encryption or sync-protocol change. Both backup
  directions excluded; Android-to-iOS remains explicitly deferred.
- No Docker image rebuild or OpenAPI regeneration: backend/contract unchanged;
  existing running-service health checked only. Remote CI result not inspected.
- A supported token is not proof of absence of PII. Common words, activities,
  schedules and provider/network metadata can still identify or correlate users.
  The allowlist limits functionality and does not support general free-form or
  multilingual cloud input. Unknown/ambiguous cases remain local for review.

BUG-005 stays open; this finishes its approved privacy portion only. Next work
must address the remaining credential/provider integration decision or another
explicitly selected bug; none is started automatically.
