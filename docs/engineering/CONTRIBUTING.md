# Contributing to Sarti

This guide applies to all contributors including AI coding assistants.
Read `AGENTS.md` and all documents it links before making any change.

## Branch and commit rules

- All work lands on `main` via reviewed commits (trunk-based development).
- Branch names are optional for local work. Codex-created branches use the
  environment-required `codex/` prefix; other branches use the team's configured
  naming convention.
- Commit messages use the conventional format:
  `type(scope): short description` where type is one of
  `feat`, `fix`, `docs`, `test`, `build`, `ci`, `refactor`, `chore`.
- Every commit that fixes a defect must reference its `BUG-NNN` ID:
  `fix(backup): conform phrase to BIP-39 spec (closes BUG-001)`.
- Never commit `.env`, credentials, keys, tokens, or build artifacts.
- Never reuse a mobile build number or move an existing release tag.
- Do not commit from a dirty working tree for a public release.

## Before opening a PR / merging

### Current maintainer workflow (approved 2026-10-12)

Use direct commits/pushes to `main` for authorized remediation; a separate
branch is not required for each fix. CI runs after each main push. A failed
run does not revert the commit automatically.

The maintainer owns test execution and pass/fail review to conserve assistant
usage. Assistants add/update tests and provide commands, but do not run tests
or inspect their logs unless explicitly asked or authorized to investigate a
reported failure. Report unexecuted tests as not run and do not claim CI passed
without evidence. The maintainer supplies failing logs or requests investigation.
Required quality gates still apply; implementation completion and verified
acceptance must be reported separately.

Run all gates locally and confirm they pass:

```sh
# Backend
make backend-check        # ruff format, ruff lint, mypy, bandit
make backend-test         # pytest unit (no integration marker)
cd backend && ../.venv/bin/pip-audit -r requirements-runtime.lock

# Mobile
make mobile-check         # dart format, flutter analyze, flutter test --coverage

# Version integrity
make version-check        # validates VERSION, BUILD_NUMBER, pubspec, __init__

# Docker smoke
make docker-up
curl --fail http://localhost:8000/v1/health/live
curl --fail http://localhost:8000/v1/health/ready
make docker-down

# OpenAPI drift (after any backend endpoint change)
cd backend && SARTI_DATABASE_URL=postgresql+psycopg://unused \
  ../.venv/bin/python scripts_generate_openapi.py
git diff --exit-code -- backend/openapi.json
```

## PR checklist

- [ ] All local gates pass (list above)
- [ ] New behavior has tests; test categories not applicable are noted with reason
- [ ] `CHANGELOG.md` `[Unreleased]` section updated
- [ ] `docs/engineering/BUGS.md` updated if a defect was fixed or discovered
- [ ] Relevant docs updated (ADR, API.md, DATABASE.md, MODULES.md, STATUS.md)
- [ ] OpenAPI regenerated and committed if endpoints changed
- [ ] Migration added to `DATABASE.md` history if schema changed
- [ ] No new secrets, credentials, or PII in any file
- [ ] Version bumped if this is a release commit (`scripts/version.py bump`)

## Version bumps

Follow `docs/engineering/RELEASES.md`. Short summary:

```sh
python3 scripts/version.py bump patch   # compatible fix
python3 scripts/version.py bump minor   # stage milestone or incompatible change
python3 scripts/version.py bump major   # incompatible public contract (post-1.0.0)
python3 scripts/version.py bump build   # new store artifact, same public version
```

After bumping: update `CHANGELOG.md` (promote `[Unreleased]` to the new version),
run all gates, commit, then create the annotated tag for a public release:

```sh
git tag -a "v$(cat VERSION)" -m "Release $(cat VERSION)"
```

## AI tool rules

These rules apply to Amazon Q, Gemini Code Assist, Codex, Copilot, and any
other AI coding assistant used in this repository.

- Read `AGENTS.md` and all mandatory documents before proposing changes.
- Apply changes within the user's authorized task scope. Ask only when a stop
  condition applies or an action is destructive, irreversible, or out of scope.
- Do not hallucinate ADR decisions. If an ADR exists, cite it exactly.
- Do not add cloud inference, silent fallbacks, or deferred-scope features
  without a new approved ADR.
- Do not remove or weaken security invariants (auth, authz, E2EE boundary,
  no plaintext family content on server, opaque FCM payload).
- If another AI tool says it completed work, inspect the repository result and
  review it against core principles before relying on the claim.
- Every AI-assisted change must pass the same gates as human changes.
- Stop and ask if a stop condition in `ENGINEERING-STANDARDS.md` is triggered.

## Defect reporting

Add new defects to `docs/engineering/BUGS.md` using the next `BUG-NNN` ID.
Include severity, component, summary, root cause if known, workaround if any,
and blocking status. Do not open a defect without at least a summary and
severity.

## What requires an ADR

- Any new external service, provider, or SDK
- Any change to the E2EE boundary, key lifecycle, or backup format
- Any change to the authentication or authorization model
- Any new data stored on the server
- Any hosting, deployment, or infrastructure decision
- Any change to an accepted ADR (requires a superseding ADR)

New ADRs use the next three-digit number in `docs/architecture/adr/` and must
be added to `docs/architecture/ADR-INDEX.md`.
