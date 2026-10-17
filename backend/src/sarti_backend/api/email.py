import base64
import hashlib
import hmac
import json
import re
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Protocol
from uuid import UUID, uuid4

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Header, Request
from nacl.public import PublicKey, SealedBox
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import and_, delete, select, update

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import InvalidRequest, PermissionDenied, TenantAccessDenied
from sarti_backend.db.schema import (
    devices,
    email_suggestion_deliveries,
    email_suggestions,
    families,
    memberships,
    permissions,
    resources,
)

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


class EncryptedEmailSuggestion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    family_id: UUID
    suggestion_id: UUID
    ciphertext: str
    received_at: datetime
    expires_at: datetime


router = APIRouter(prefix="/v1/email", tags=["email"])
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]


def _email_scope() -> Any:
    # Full household email is never delivered to a care-calendar-only recipient.
    return (
        select(resources.c.id)
        .join(permissions, permissions.c.resource_id == resources.c.id)
        .join(families, families.c.id == resources.c.family_id)
        .where(
            resources.c.family_id == memberships.c.family_id,
            resources.c.kind == "calendar",
            resources.c.deleted_at.is_(None),
            families.c.context_kind == "household",
            families.c.deleted_at.is_(None),
            permissions.c.adult_id == memberships.c.adult_id,
            permissions.c.permission.in_(("read", "write", "admin")),
            memberships.c.role.in_(("owner", "administrator", "guardian")),
            (memberships.c.expires_at.is_(None) | (memberships.c.expires_at > datetime.now(UTC))),
        )
        .exists()
    )


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
        connection.execute(delete(email_suggestions).where(email_suggestions.c.expires_at <= now))
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

        recipients = connection.execute(
            select(devices.c.id, devices.c.encryption_public_key)
            .join(memberships, memberships.c.adult_id == devices.c.adult_id)
            .where(
                and_(
                    memberships.c.family_id == family_id,
                    memberships.c.status == "active",
                    _email_scope(),
                    devices.c.state == "active",
                )
            )
        ).all()
        if not recipients:
            raise InvalidRequest("No active authorized device can receive this email.")

        suggestion_id = uuid4()
        plaintext = json.dumps(
            {
                "version": 2,
                "family_id": str(family_id),
                "suggestion_id": str(suggestion_id),
                "sender": payload.sender,
                "subject": subject,
                "body": body,
                "received_at": now.isoformat(),
            },
            separators=(",", ":"),
        ).encode()
        deliveries = [
            {
                "suggestion_id": suggestion_id,
                "device_id": recipient.id,
                "ciphertext": SealedBox(PublicKey(recipient.encryption_public_key)).encrypt(
                    plaintext
                ),
                "status": "pending",
                "created_at": now,
            }
            for recipient in recipients
        ]
        connection.execute(
            email_suggestions.insert().values(
                id=suggestion_id,
                family_id=family_id,
                content_digest=content_digest,
                received_at=now,
                expires_at=expires_at,
            )
        )
        connection.execute(email_suggestion_deliveries.insert(), deliveries)

    return EmailSuggestionResponse(
        suggestion_id=suggestion_id,
        expires_at=expires_at,
    )


@router.get("/suggestions", response_model=list[EncryptedEmailSuggestion])
def list_suggestions(request: Request, actor: Authenticated) -> list[EncryptedEmailSuggestion]:
    database: TransactionalDatabase = request.app.state.database
    now = datetime.now(UTC)
    with database.transaction() as connection:
        connection.execute(delete(email_suggestions).where(email_suggestions.c.expires_at <= now))
        rows = connection.execute(
            select(
                email_suggestions.c.id,
                email_suggestions.c.family_id,
                email_suggestion_deliveries.c.ciphertext,
                email_suggestions.c.received_at,
                email_suggestions.c.expires_at,
            )
            .join(
                email_suggestion_deliveries,
                email_suggestion_deliveries.c.suggestion_id == email_suggestions.c.id,
            )
            .join(
                memberships,
                and_(
                    memberships.c.family_id == email_suggestions.c.family_id,
                    memberships.c.adult_id == actor.adult_id,
                    memberships.c.status == "active",
                ),
            )
            .where(
                and_(
                    email_suggestion_deliveries.c.device_id == actor.device_id,
                    _email_scope(),
                    email_suggestion_deliveries.c.status == "pending",
                    email_suggestions.c.expires_at > now,
                )
            )
            .order_by(email_suggestions.c.received_at)
        ).all()
    return [
        EncryptedEmailSuggestion(
            family_id=row.family_id,
            suggestion_id=row.id,
            ciphertext=base64.urlsafe_b64encode(row.ciphertext).rstrip(b"=").decode("ascii"),
            received_at=row.received_at,
            expires_at=row.expires_at,
        )
        for row in rows
    ]


@router.delete("/suggestions/{suggestion_id}", status_code=204)
def dismiss_suggestion(suggestion_id: UUID, request: Request, actor: Authenticated) -> None:
    database: TransactionalDatabase = request.app.state.database
    with database.transaction() as connection:
        result = connection.execute(
            update(email_suggestion_deliveries)
            .where(
                and_(
                    email_suggestion_deliveries.c.suggestion_id == suggestion_id,
                    email_suggestion_deliveries.c.device_id == actor.device_id,
                    email_suggestion_deliveries.c.status == "pending",
                )
            )
            .values(status="dismissed")
        )
        if result.rowcount != 1:
            raise TenantAccessDenied
