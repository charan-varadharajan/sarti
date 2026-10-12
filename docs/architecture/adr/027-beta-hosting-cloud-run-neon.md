# ADR-027: Cloud Run and Neon Free for beta hosting

- Status: Accepted
- Date: 2026-10-11
- Supersedes: the hosting-undecided portion of ADR-018 for development and beta
  environments only

## Decision

Deploy the FastAPI container to Google Cloud Run using request-based billing,
zero minimum instances, and a small bounded maximum instance count. Use a Neon
Free PostgreSQL project for development and the initial private beta.

Keep Docker Compose as the local development standard. Keep production hosting
unresolved until Sarti has passed the Stage 3 privacy and physical-device gates
and the selected database plan provides an approved backup, recovery,
availability, data-region, retention, and deletion posture.

## Constraints

- Cloud Run and Neon must communicate over TLS.
- Database credentials and provider credentials must use managed runtime secrets;
  they must not be committed or embedded in the mobile application.
- Alembic migrations run as an explicit deployment step before new application
  code receives traffic.
- Cloud Run must retain scale-to-zero behavior during beta; enabling minimum
  instances or instance-based billing requires a cost review.
- A billing budget and alerts are required before deployment.
- The free database tier is not treated as a backup. Export and restore testing
  is required before real family data is admitted.
- Provider logs and metrics must follow ADR-016 and contain no family content,
  credentials, keys, raw ciphertext, or email bodies.

## Consequences

The existing Docker image and PostgreSQL schema remain portable. Low beta traffic
can remain within provider free allowances, but cold starts and free-tier limits
are accepted for beta. Production launch still requires a separate approval
covering paid capacity, backups, recovery objectives, availability, region,
subprocessors, monitoring, and exit procedures.
