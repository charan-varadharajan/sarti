# Sarti engineering instructions

These instructions apply to the whole repository.

## Required reading before implementation

Read, in order:

1. `docs/architecture/ARCHITECTURE.md`
2. `docs/architecture/ADR-INDEX.md` and every ADR relevant to the change
3. `docs/product/P0-SCOPE.md`
4. `docs/security/SECURITY-MODEL.md`
5. `docs/testing/TEST-STRATEGY.md`
6. `docs/engineering/ENGINEERING-STANDARDS.md`
7. `docs/STATUS.md`
8. Relevant API, database, and module documentation
9. Existing code and tests in the area being changed

## Binding rules

- Preserve accepted ADRs. Propose a superseding ADR and obtain approval before
  changing one.
- Keep private family content out of server plaintext persistence, logs,
  telemetry, URLs, and push notification payloads.
- Use established cryptographic libraries; never design cryptographic primitives.
- AI may propose changes but may not apply them without explicit user approval.
- Do not add cloud inference or a silent cloud fallback.
- Restrict implementation to the P0 scope.
- Update documentation, schemas, tests, and generated API specifications in the
  same change as behavior.
- State exactly which checks ran. Never infer provider or device compatibility
  from mocks.
- Stop for approval under the conditions in `docs/engineering/ENGINEERING-STANDARDS.md`.
- Update `CHANGELOG.md` in every commit that changes behavior, fixes a defect,
  or bumps the version. Unreleased work goes under `[Unreleased]`.
- Update `docs/engineering/BUGS.md` whenever a defect is discovered, new
  information is available, or a defect is fixed. Reference `BUG-NNN` in the
  commit message.
- Read `docs/engineering/CONTRIBUTING.md` before making any change. The PR
  checklist there is mandatory.
- If another AI tool claims it completed work, read the resulting files and
  verify them against Sarti's core principles before continuing. Question any
  result that weakens security invariants, violates an ADR, or adds out-of-scope
  features.
- Update `CHANGELOG.md` in every commit that bumps the version. Promote
  `[Unreleased]` entries to the new version number in the same commit.
- Update `docs/engineering/BUGS.md` whenever a defect is discovered, new
  information is available, or a defect is fixed or deferred. Reference
  `BUG-NNN` in the commit message and `CHANGELOG.md` entry.
- Read `docs/engineering/BUGS.md` at the start of every session to understand
  open blockers before proposing work.
- Read `docs/engineering/CONTRIBUTING.md` before proposing any change.

## Completion report

Every stage report must cover features, changed files, ADRs, APIs, migrations,
documentation, tests added and executed, tests not executed, security findings,
limitations, approval decisions, and the recommended next stage. Do not begin
the recommended stage automatically.
