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
- Apply changes within the user's authorized task scope. Obtain approval only
  when a documented stop condition applies or the action is destructive,
  irreversible, or outside that scope.
- Do not add cloud inference or a silent cloud fallback.
- Restrict implementation to the P0 scope.
- Update documentation, schemas, tests, and generated API specifications in the
  same change as behavior.
- State exactly which checks ran. Never infer provider or device compatibility
  from mocks.
- Add or update the stable scenario entry in
  `docs/testing/TEST-SCENARIOS.md` with every functional journey. Use prepared
  fixtures and direct target-screen entry; create prerequisites through UI only
  when prerequisite creation is itself under test.
- Stop for approval under the conditions in `docs/engineering/ENGINEERING-STANDARDS.md`.
- Read `docs/engineering/CONTRIBUTING.md` and
  `docs/engineering/BUGS.md` before making a change. The PR checklist is
  mandatory, and open blockers must inform the plan.
- Update `CHANGELOG.md` under `[Unreleased]` in every commit that changes
  behavior, fixes a defect, or bumps the version. A version bump promotes the
  accumulated entries in the same commit.
- Update `docs/engineering/BUGS.md` whenever a defect is discovered, fixed,
  deferred, or materially clarified. Reference `BUG-NNN` in the fixing commit
  and changelog entry.
- If another AI tool claims it completed work, read the resulting files and
  verify them against Sarti's core principles before continuing. Question any
  result that weakens security invariants, violates an ADR, or adds out-of-scope
  features.

## Privacy claims

Follow `docs/product/PRIVACY-MESSAGING.md` for public, store, pamphlet and in-app
copy. Distinguish encrypted storage/sync/backup, native AI, optional cloud AI and
plaintext email processing. Never claim personal information cannot leave the
phone, that pseudonymization is anonymity, or provider retention/training
properties without verified deployment-specific evidence.

## Completion report

Every stage report must cover features, changed files, ADRs, APIs, migrations,
documentation, tests added and executed, tests not executed, security findings,
limitations, approval decisions, and the recommended next stage. Do not begin
the recommended stage automatically.
