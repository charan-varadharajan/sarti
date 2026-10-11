# Engineering standards

## Workflow

Analyze → Design → Document → Implement → Test → Review → Update documentation →
Report. Work in small, reviewable changes.

## Code and design

- Prefer explicit modules, strict typing, and simple interfaces.
- Keep domain logic independent of frameworks and providers.
- Validate all boundary input and return structured, stable errors.
- Do not swallow exceptions or log raw inputs by default.
- Do not hardcode credentials or production configuration.
- Avoid speculative infrastructure and premature abstraction.
- Review dependency maintenance, security, license, compatibility, and transitive
  impact before adoption.
- Never implement custom cryptographic primitives.

## Documentation requirements

Behavior changes include the relevant architecture, ADR, API, database, module,
operations, and status updates. FastAPI-generated OpenAPI is the API source of
truth and is checked for drift. Every migration has an entry in migration history.

## Review and completion

A change is complete only when requirements, documentation, applicable tests,
security checks, API/schema synchronization, migration checks, regression
coverage, and complexity review pass. Critical or high-severity vulnerabilities
and unexplained test failures block completion.

## Stop conditions

Stop and obtain approval if an accepted ADR must change; a security guarantee
cannot be met; an SDK fails privacy requirements; a service adds unexpected cost
or exposure; a dependency has material security or licensing concerns; a
fundamental architecture assumption fails; or work exceeds P0.

## Repository conventions

- Python targets 3.13 with Ruff formatting/lint and strict Mypy.
- Flutter uses its generated analysis configuration and `dart format`.
- Direct and resolved dependencies are pinned; lock files are committed.
- FastAPI generates `backend/openapi.json`; manual edits are prohibited.
- Alembic revisions are append-only after merge and must have migration tests.
- CI runs on pushes to `main` and pull requests. Required checks should be branch
  protected when repository settings are configured.
- Build products, local environments, coverage output, and secrets are ignored.
- Release versioning and production branching remain unresolved until the first
  release plan.
