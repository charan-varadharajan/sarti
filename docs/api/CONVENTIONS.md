# API conventions

- Version public application routes under `/v1`.
- Use JSON with UTF-8 and UTC RFC 3339 timestamps when timestamps are needed.
- Return structured errors as `{error: {code, message, request_id}}`.
- Generate a request ID when a valid bounded incoming ID is absent; return it in
  `X-Request-ID` and safe operational logs.
- Reject unexpected or invalid input through FastAPI/Pydantic validation.
- Document authentication, authorization, idempotency, status/error codes,
  privacy effects, and examples for every endpoint.
- Generate OpenAPI from the application and detect committed-spec drift in CI.
- Do not place tokens, family content, email content, or sensitive identifiers in
  paths or query strings.

Pagination, mutation idempotency keys, authentication headers, and compatibility
policy remain unresolved until the first protected API is designed.
