# API documentation

The generated OpenAPI 3.1 contract is committed at `backend/openapi.json` and
checked for drift in tests and CI. Both Stage 1 endpoints belong to the health
module and expose no family content.

Interactive documentation and a runtime OpenAPI route are disabled in the Stage
1 service. Consumers use the reviewed committed contract.

## `GET /v1/health/live`

- Purpose: report that the API process can handle a request.
- Authentication/authorization: none; suitable for local/container liveness.
- Request body and parameters: none.
- Success: `200 {"status":"ok"}`.
- Validation/errors: no request input; unexpected failures use the standard
  sanitized error envelope.
- Idempotency: safe and idempotent.
- Privacy: does not access PostgreSQL or private content.

```sh
curl -i http://localhost:8000/v1/health/live
```

## `GET /v1/health/ready`

- Purpose: report whether the API can execute a PostgreSQL `SELECT 1`.
- Authentication/authorization: none; suitable for local/container readiness.
- Request body and parameters: none.
- Success: `200 {"status":"ready"}`.
- Unavailable: `503 {"status":"unavailable"}`.
- Idempotency: safe and idempotent.
- Privacy: returns no connection, schema, exception, or content details.

```sh
curl -i http://localhost:8000/v1/health/ready
```

Both endpoints return a UUID in `X-Request-ID`. A valid incoming UUID may be
propagated; arbitrary incoming values are replaced so caller-controlled content
cannot be placed into logs. See `CONVENTIONS.md` for the standard error envelope
and future endpoint requirements.
