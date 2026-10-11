# ADR-004: PostgreSQL operational metadata

- Status: Accepted
- Date: 2026-10-11

Use PostgreSQL for server operational metadata. It may contain authorization and
device state, job data, and encrypted relay payloads; it must not persist private
family content in plaintext. Detailed schemas require data classification first.
