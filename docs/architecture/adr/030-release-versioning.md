# ADR-030: Release versioning

- Status: Accepted
- Date: 2026-10-11

## Decision

Sarti uses one repository-wide public version for the Flutter app and backend.
The public version follows Semantic Versioning as `MAJOR.MINOR.PATCH`. Mobile
artifacts append a positive, monotonically increasing build number using
Flutter's `MAJOR.MINOR.PATCH+BUILD` syntax.

`VERSION` and `BUILD_NUMBER` are the canonical values. The version tool keeps
`mobile/pubspec.yaml` and `sarti_backend.__version__` synchronized. CI rejects
drift. A release tag is exactly `vMAJOR.MINOR.PATCH` and CI rejects a tag that
does not match `VERSION`.

## Increment rules

- Before `1.0.0`, increment **minor** for a stage milestone or any incompatible
  product/API/schema contract change; reset patch to zero.
- Increment **patch** for compatible fixes and compatible implementation
  additions within the current stage.
- Increment **build** for another store/distribution artifact of the same public
  version. Every public-version bump also increments build.
- At and after `1.0.0`, increment **major** for incompatible public contracts,
  **minor** for backward-compatible features, and **patch** for compatible fixes.
- Database and backup-format versions remain independent protocol numbers. They
  change only under their migration and ADR rules.

## Release workflow

Run `python3 scripts/version.py bump minor|patch|major|build`, review all changed
version surfaces, run quality gates, merge, then create the matching annotated
Git tag for a public release. CI validates ordinary commits and release tags.
Creating or publishing a release remains an explicit human action.
