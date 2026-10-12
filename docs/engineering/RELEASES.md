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

After a public-version bump, run repository quality gates and commit the version
changes with the release work. A public release uses an annotated tag matching
`v$(cat VERSION)`. Never reuse a mobile build number, move an existing release
tag, or publish from a dirty working tree.

The first production release is `1.0.0`. Until then, stage milestones increment
minor and compatible remediation increments patch. CI validates the canonical
files, Flutter manifest, backend package, and release tags.

Production branching remains trunk based: reviewed work lands on `main`; release
tags identify immutable public releases. A maintenance branch may be created
only when a supported production version requires fixes separate from `main`.
