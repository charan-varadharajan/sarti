# ADR-002: FastAPI modular-monolith backend

- Status: Accepted
- Date: 2026-10-11

Use Python and FastAPI in one deployable modular monolith. Modules own interfaces
and persistence access; framework and transport code depend on application code,
not the reverse. Splitting services requires a future approved ADR.
