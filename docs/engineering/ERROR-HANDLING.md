# Error handling

Domain/application failures use stable typed codes. The HTTP adapter maps known
safe failures to a structured response. Validation errors receive a stable code.
Unexpected failures return a generic message and correlation ID; details remain
in sanitized server logs.

Never return stack traces, database details, secrets, raw input, family content,
or provider payloads. Never silently swallow errors. Readiness reports only
`ready` or `unavailable` and does not reveal connection information.
