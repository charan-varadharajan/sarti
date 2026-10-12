import hashlib
import hmac
import re
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Protocol
from uuid import UUID, uuid4

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Header, Request
from pydantic import BaseModel, ConfigDict, Field

from sarti_backend.core.errors import InvalidRequest, PermissionDenied, TenantAccessDenied

_MAX_BODY_BYTES = 102_400  # 100 KB
_MAX_EMAILS_PER_DAY = 20
_SUGGESTION_TTL_DAYS = 7

# Prompt injection: characters that could break delimiter context
_INJECTION_PATTERN = re.compile(r"</?INPUT>", re.IGNORECASE)


class TransactionalDatabase(Protocol):
    def transaction(self) -> Any: ...

    def connect(self) -> Any: ...


class EmailIngestPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    family_token: str = Field(min_length=16, max_length=256)
    sender: str = Field(min_length=1, max_length=320)
    subject: str = Field(default="", max_length=998)
    body: str = Field(default="", max_length=_MAX_BODY_BYTES)


class EmailSuggestionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    suggestion_id: UUID
    expires_at: datetime


router = APIRouter(prefix="/v1/email", tags=["email"])


def _require_worker_secret(
    request: Request,
    x_worker_secret: Annotated[str | None, Header()] = None,
) -> None:
    expected = request.app.state.settings.email_worker_secret
    if not expected:
        raise PermissionDenied
    if x_worker_secret is None:
        raise PermissionDenied
    if not hmac.compare_digest(
        hashlib.sha256(x_worker_secret.encode()).digest(),
        hashlib.sha256(expected.encode()).digest(),
    ):
        raise PermissionDenied


WorkerAuth = Annotated[None, Depends(_require_worker_secret)]


@router.post("/ingest", response_model=EmailSuggestionResponse, status_code=201)
def ingest_email(
    payload: EmailIngestPayload,
    request: Request,
    _: WorkerAuth,
) -> EmailSuggestionResponse:
    from sarti_backend.db.schema import email_suggestions, families

    database: TransactionalDatabase = request.app.state.database

    # Sanitize: strip injection attempts from body and subject
    body = _INJECTION_PATTERN.sub("", payload.body)[:_MAX_BODY_BYTES]
    subject = _INJECTION_PATTERN.sub("", payload.subject)[:998]

    # Deduplicate by content hash
    content_digest = hashlib.sha256(
        f"{payload.family_token}:{payload.sender}:{subject}:{body}".encode()
    ).digest()

    now = datetime.now(UTC)
    expires_at = now + timedelta(days=_SUGGESTION_TTL_DAYS)

    with database.transaction() as connection:
        # Resolve family token → family_id
        token_digest = hashlib.sha256(payload.family_token.encode()).digest()
        family_row = (
            connection.execute(
                families.select().where(families.c.email_token_digest == token_digest)
            )
            .mappings()
            .one_or_none()
        )
        if family_row is None:
            raise TenantAccessDenied

        family_id: UUID = family_row["id"]

        # Rate limit: max 20 emails per family per 24 hours
        window_start = now - timedelta(hours=24)
        recent_count = connection.execute(
            sa.select(sa.func.count()).select_from(
                email_suggestions.select()
                .where(
                    email_suggestions.c.family_id == family_id,
                    email_suggestions.c.received_at >= window_start,
                )
                .subquery()
            )
        ).scalar_one()
        if recent_count >= _MAX_EMAILS_PER_DAY:
            raise InvalidRequest("Email rate limit exceeded for this family.")

        # Duplicate check
        existing = (
            connection.execute(
                email_suggestions.select().where(
                    email_suggestions.c.content_digest == content_digest
                )
            )
            .mappings()
            .one_or_none()
        )
        if existing is not None:
            return EmailSuggestionResponse(
                suggestion_id=existing["id"],
                expires_at=existing["expires_at"],
            )

        suggestion_id = uuid4()
        connection.execute(
            email_suggestions.insert().values(
                id=suggestion_id,
                family_id=family_id,
                sender=payload.sender,
                subject_sanitized=subject,
                body_sanitized=body,
                content_digest=content_digest,
                status="pending",
                received_at=now,
                expires_at=expires_at,
            )
        )

    return EmailSuggestionResponse(
        suggestion_id=suggestion_id,
        expires_at=expires_at,
    )
