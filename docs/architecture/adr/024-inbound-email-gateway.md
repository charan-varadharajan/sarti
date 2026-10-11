# ADR-024: Inbound email gateway

- Status: Accepted
- Date: 2026-10-12

## Decision

Cloudflare Email Routing forwards inbound family email to a Cloudflare Worker.
The Worker validates the sender, strips headers, and POSTs a sanitized payload
to the Sarti FastAPI backend over HTTPS. Raw email is never stored by Sarti.

## Plaintext boundary

Email is unavoidably plaintext from sender to the Cloudflare Worker and through
the Worker-to-backend POST. The plaintext boundary ends when the backend
produces an encrypted suggestion payload and stores only ciphertext. No raw
email body, subject, or sender address is written to PostgreSQL in plaintext
after the suggestion is produced.

## Pipeline

1. Sender sends email to `family-<token>@sarti.app`.
2. Cloudflare Email Routing delivers to a Cloudflare Worker.
3. Worker checks: sender domain not on blocklist, message size within limit
   (100 KB), no executable attachments. Rejects silently on failure.
4. Worker extracts: sender address, subject, plain-text body only (HTML
   stripped). Attachments are discarded.
5. Worker POSTs `{family_token, sender, subject, body}` to
   `POST /v1/email/ingest` over HTTPS with a shared secret header.
6. Backend validates the shared secret, resolves `family_token` to a
   `family_id`, verifies the family exists and has email ingestion enabled.
7. Backend passes `{sender, subject, body}` to the suggestion pipeline. The
   family_id is never included in any AI prompt.
8. Suggestion pipeline produces a structured `EmailSuggestion` record stored
   as ciphertext in PostgreSQL with a 7-day TTL.
9. On next sync, authorized devices download the encrypted suggestion, decrypt
   locally, and present it as a proposal requiring explicit approval.

## Prompt injection protection

- Email body is treated as untrusted string data throughout.
- The AI prompt wraps the body in explicit delimiters and instructs the model
  that content inside the delimiters is untrusted user data, not instructions.
- Model output is validated against a strict JSON schema. Any response that
  does not conform is discarded.
- Email content cannot set permissions, modify instructions, or trigger any
  action other than producing a structured suggestion for human review.

## Sender validation and abuse controls

- Family email address uses a random 128-bit token, not a guessable identifier.
- Sender domain blocklist checked by the Worker.
- Maximum 20 inbound emails per family per 24 hours (enforced by backend).
- Duplicate detection by SHA-256 of `(family_id, sender, subject, body)`.
- Families may disable email ingestion entirely.

## Retention and deletion

- Raw email is never stored by Sarti (Worker discards after POST).
- Encrypted suggestion records expire after 7 days (same TTL as sync relay).
- Cloudflare Worker logs contain only: timestamp, family_token hash, sender
  domain, accept/reject decision. No email body or subject in logs.

## Open items resolved before implementation

- `SARTI_EMAIL_WORKER_SECRET` added to backend config.
- `SARTI_GEMINI_API_KEY` optional; if absent, deterministic parser used.
- Cloudflare Worker source committed to `backend/cloudflare/email_worker.js`.
- Family email token provisioned at family creation.
