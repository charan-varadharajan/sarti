# Release and version policy

The current public version is stored in `VERSION`; the mobile build number is in
`BUILD_NUMBER`. Do not edit generated version surfaces independently.

## Commands

```sh
python3 scripts/version.py check
python3 scripts/version.py bump patch
python3 scripts/version.py bump minor
python3 scripts/version.py bump major
python3 scripts/version.py bump build
```

After a public-version bump:

1. Update `CHANGELOG.md` — promote the `[Unreleased]` section to the new
   version with today's date. Add a summary of what changed.
2. Update `docs/engineering/BUGS.md` — confirm all fixed defects are moved to
   the Resolved section with the new version number.
3. Run all repository quality gates (`make backend-check backend-test
   mobile-check version-check`).
4. Commit all version surfaces and documentation together.
5. For a public release, create an annotated tag: `git tag -a "v$(cat VERSION)"
   -m "Release $(cat VERSION)"`.

Never reuse a mobile build number, move an existing release tag, or publish
from a dirty working tree.

The first production release is `1.0.0`. Until then, stage milestones increment
minor and compatible remediation increments patch. CI validates the canonical
files, Flutter manifest, backend package, and release tags.

Production branching remains trunk based: reviewed work lands on `main`; release
tags identify immutable public releases. A maintenance branch may be created
only when a supported production version requires fixes separate from `main`.
