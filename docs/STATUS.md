# Project status

- Current stage: Stage 1 — foundation documentation
- Updated: 2026-10-11
- Repository state: no application code, schemas, dependencies, or CI
- Stage state: ready for review

## Stage 1 delivered

- Repository working instructions and project entry point
- P0 scope and deferred-scope boundary
- System context, trust boundaries, components, and principal data flows
- Five accepted baseline ADRs derived from the engineering contract
- Initial threat model and security invariants
- Test strategy and quality gates
- Engineering, API, database, module, and operations documentation baselines

## Decisions still required before affected implementation

1. Detailed resource/key hierarchy and cryptographic protocol
2. Sync operation model and deterministic conflict rules
3. Passkey and platform secure-storage integrations
4. Verified native AI capabilities and supported OS/device matrix
5. Email gateway provider and plaintext minimization design
6. Push integration and opaque payload format
7. Backup format, recovery UX, and key custody
8. Data classification matrix and metadata retention schedule
9. Flutter and Python versions and dependency selections
10. Production hosting and operational vendors (not required for local scaffolding)

## Known limitations

- Architecture details above the contract baseline are intentionally undecided.
- There is no executable product, OpenAPI document, schema, migration, CI, or test
  suite yet.
- Flutter is not installed on the observed development workstation.
- Real-device, provider, cryptographic, and database behavior has not been tested.

## Recommended next stage

Stage 2: propose and review the repository/toolchain scaffold plus the detailed
identity, authorization, data classification, and key-management design needed
for onboarding. Do not begin Stage 2 until Stage 1 is approved.
