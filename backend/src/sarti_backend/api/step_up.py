"""Bounded current-phone reauthentication; content-free operational binding."""

import hashlib
import json
import secrets
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import and_, delete, func, select, update
from webauthn.helpers import base64url_to_bytes

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import ConflictDetected, InvalidCredential
from sarti_backend.db.schema import credentials, sensitive_authorizations
from sarti_backend.identity.step_up import check_scope, current_session

Action = Literal[
    "admin.change",
    "permissions.change",
    "membership.revoke",
    "household.close",
    "account.delete",
    "export",
    "event.restore",
]
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]
router = APIRouter(prefix="/v1/auth/step-up", tags=["authentication"])


class StepUpBinding(BaseModel):
    model_config = ConfigDict(extra="forbid")
    action: Action
    family_id: UUID | None = None
    target_id: UUID
    acl_revision: int = Field(ge=0)

    @model_validator(mode="after")
    def context_kind(self) -> "StepUpBinding":
        if (self.action == "account.delete") != (self.family_id is None):
            raise ValueError("invalid action scope")
        return self


class StepUpOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    challenge_id: UUID
    public_key: dict[str, Any]
    expires_at: datetime


class StepUpCompletion(BaseModel):
    model_config = ConfigDict(extra="forbid")
    challenge_id: UUID
    credential: dict[str, Any]

    @model_validator(mode="after")
    def bound(self) -> "StepUpCompletion":
        if len(json.dumps(self.credential, separators=(",", ":"))) > 65536:
            raise ValueError("credential too large")
        return self


class StepUpProof(BaseModel):
    model_config = ConfigDict(extra="forbid")
    proof: str
    expires_at: datetime


@router.post("/options", response_model=StepUpOptions)
def options(payload: StepUpBinding, request: Request, actor: Authenticated) -> StepUpOptions:
    challenge_id = uuid4()
    challenge = secrets.token_bytes(32)
    expires = datetime.now(UTC) + timedelta(minutes=5)
    with request.app.state.database.transaction() as connection:
        session_id = current_session(connection, request, actor)
        check_scope(connection, actor, payload.family_id, payload.target_id, payload.acl_revision)
        connection.execute(
            delete(sensitive_authorizations).where(
                sensitive_authorizations.c.expires_at <= datetime.now(UTC)
            )
        )
        if (
            connection.execute(
                select(func.count())
                .select_from(sensitive_authorizations)
                .where(sensitive_authorizations.c.session_id == session_id)
            ).scalar_one()
            >= 20
        ):
            raise ConflictDetected("Too many pending confirmations. Try again later.")
        connection.execute(
            sensitive_authorizations.insert().values(
                id=challenge_id,
                session_id=session_id,
                action=payload.action,
                family_id=payload.family_id,
                target_id=payload.target_id,
                acl_revision=payload.acl_revision,
                challenge=challenge,
                expires_at=expires,
            )
        )
    return StepUpOptions(
        challenge_id=challenge_id,
        public_key=request.app.state.webauthn.authentication_options(challenge=challenge),
        expires_at=expires,
    )


@router.post("/complete", response_model=StepUpProof)
def complete(payload: StepUpCompletion, request: Request, actor: Authenticated) -> StepUpProof:
    try:
        credential_id = base64url_to_bytes(str(payload.credential["id"]))
    except (KeyError, TypeError, ValueError) as error:
        raise InvalidCredential from error
    with request.app.state.database.transaction() as connection:
        row = (
            connection.execute(
                select(sensitive_authorizations)
                .where(sensitive_authorizations.c.id == payload.challenge_id)
                .with_for_update()
            )
            .mappings()
            .one_or_none()
        )
        if (
            row is None
            or row["verified_at"] is not None
            or row["consumed_at"] is not None
            or row["expires_at"] <= datetime.now(UTC)
        ):
            raise InvalidCredential
        check_scope(connection, actor, row["family_id"], row["target_id"], row["acl_revision"])
        credential = (
            connection.execute(
                select(credentials)
                .where(
                    and_(
                        credentials.c.credential_id == credential_id,
                        credentials.c.adult_id == actor.adult_id,
                    )
                )
                .with_for_update()
            )
            .mappings()
            .one_or_none()
        )
        if credential is None:
            raise InvalidCredential
        session_id = current_session(connection, request, actor)
        if row["session_id"] != session_id:
            raise InvalidCredential
        try:
            result = request.app.state.webauthn.verify_authentication(
                credential=payload.credential,
                challenge=row["challenge"],
                credential_public_key=credential["public_key"],
                current_sign_count=credential["sign_count"],
            )
        except Exception as error:
            raise InvalidCredential from error
        proof = secrets.token_urlsafe(32)
        connection.execute(
            update(credentials)
            .where(credentials.c.credential_id == credential_id)
            .values(sign_count=result.new_sign_count)
        )
        connection.execute(
            update(sensitive_authorizations)
            .where(sensitive_authorizations.c.id == row["id"])
            .values(
                verified_at=datetime.now(UTC),
                proof_digest=hashlib.sha256(proof.encode("ascii")).digest(),
            )
        )
    return StepUpProof(proof=proof, expires_at=row["expires_at"])
