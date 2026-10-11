# Tenant isolation

The family is the tenant boundary. Authentication, active-device validation,
family membership, role, and resource authorization are separate checks.

The backend provides a typed tenant context and a fail-closed family assertion
that future protected repositories must require. Stage 1 tests prove mismatched
family IDs are rejected, but there are no protected resource endpoints or family
tables yet. Each future repository query must include family scope and have a
negative two-family integration test. PostgreSQL row-level security is unresolved
and may supplement, but never replace, application authorization.
