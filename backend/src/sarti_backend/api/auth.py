import base64
import binascii
import hashlib
import json
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol
from uuid import UUID, uuid4

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import Connection, and_, select, update
from webauthn.helpers import base64url_to_bytes

from sarti_backend.core.errors import ConflictDetected, InvalidCredential
from sarti_backend.db.schema import adults, challenges, credentials, devices, sessions
from sarti_backend.households.device_replacement import advance_replacement_epochs
from sarti_backend.identity.webauthn_service import WebAuthnVerifier


class TransactionalDatabase(Protocol):
    def transaction(self) -> Any: ...


class DeviceKeys(BaseModel):
    model_config = ConfigDict(extra="forbid")

    encryption_public_key: str = Field(min_length=43, max_length=44)
    signing_public_key: str = Field(min_length=43, max_length=44)


class CeremonyCompletion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    challenge_id: UUID
    credential: dict[str, Any]
    device_keys: DeviceKeys

    @model_validator(mode="after")
    def bound_credential(self) -> "CeremonyCompletion":
        if len(json.dumps(self.credential, separators=(",", ":"))) > 65_536:
            raise ValueError("credential exceeds maximum size")
        return self


class CeremonyOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")

    challenge_id: UUID
    public_key: dict[str, Any]


class SessionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    adult_id: UUID
    device_id: UUID
    session_token: str
    expires_at: datetime


router = APIRouter(prefix="/v1/auth", tags=["authentication"])


def _decode_key(value: str) -> bytes:
    try:
        result = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except (ValueError, binascii.Error) as error:
        raise InvalidCredential from error
    if len(result) != 32:
        raise InvalidCredential
    return result


def _consume_challenge(
    connection: Connection, challenge_id: UUID, expected_kind: str
) -> tuple[bytes, UUID | None]:
    row = (
        connection.execute(
            select(challenges).where(challenges.c.id == challenge_id).with_for_update()
        )
        .mappings()
        .one_or_none()
    )
    now = datetime.now(UTC)
    if (
        row is None
        or row["kind"] != expected_kind
        or row["consumed_at"] is not None
        or row["expires_at"] <= now
    ):
        raise InvalidCredential
    connection.execute(
        update(challenges).where(challenges.c.id == challenge_id).values(consumed_at=now)
    )
    return row["challenge"], row["prospective_adult_id"]


def _new_session(connection: Connection, adult_id: UUID, device_id: UUID) -> SessionResponse:
    token = secrets.token_urlsafe(32)
    expires_at = datetime.now(UTC) + timedelta(days=30)
    connection.execute(
        sessions.insert().values(
            id=uuid4(),
            token_digest=hashlib.sha256(token.encode("ascii")).digest(),
            adult_id=adult_id,
            device_id=device_id,
            expires_at=expires_at,
            revoked_at=None,
            created_at=datetime.now(UTC),
        )
    )
    return SessionResponse(
        adult_id=adult_id,
        device_id=device_id,
        session_token=token,
        expires_at=expires_at,
    )


@router.post("/registration/options", response_model=CeremonyOptions)
def registration_options(request: Request) -> CeremonyOptions:
    challenge_id = uuid4()
    adult_id = uuid4()
    challenge = secrets.token_bytes(32)
    verifier: WebAuthnVerifier = request.app.state.webauthn
    database: TransactionalDatabase = request.app.state.database
    with database.transaction() as connection:
        connection.execute(
            challenges.insert().values(
                id=challenge_id,
                kind="registration",
                challenge=challenge,
                prospective_adult_id=adult_id,
                expires_at=datetime.now(UTC) + timedelta(minutes=5),
                consumed_at=None,
                created_at=datetime.now(UTC),
            )
        )
    return CeremonyOptions(
        challenge_id=challenge_id,
        public_key=verifier.registration_options(
            challenge=challenge,
            user_id=adult_id.bytes,
            user_name=f"account-{adult_id}",
        ),
    )


@router.post("/registration/complete", response_model=SessionResponse, status_code=201)
def registration_complete(payload: CeremonyCompletion, request: Request) -> SessionResponse:
    verifier: WebAuthnVerifier = request.app.state.webauthn
    database: TransactionalDatabase = request.app.state.database
    with database.transaction() as connection:
        challenge, adult_id = _consume_challenge(connection, payload.challenge_id, "registration")
        if adult_id is None:
            raise InvalidCredential
        try:
            verified = verifier.verify_registration(
                credential=payload.credential,
                challenge=challenge,
            )
        except Exception as error:
            raise InvalidCredential from error
        if connection.execute(
            select(credentials.c.credential_id).where(
                credentials.c.credential_id == verified.credential_id
            )
        ).first():
            raise ConflictDetected("This passkey is already registered.")
        now = datetime.now(UTC)
        device_id = uuid4()
        connection.execute(
            adults.insert().values(
                id=adult_id,
                webauthn_user_handle=adult_id.bytes,
                created_at=now,
            )
        )
        connection.execute(
            credentials.insert().values(
                credential_id=verified.credential_id,
                adult_id=adult_id,
                public_key=verified.credential_public_key,
                sign_count=verified.sign_count,
                created_at=now,
            )
        )
        connection.execute(
            devices.insert().values(
                id=device_id,
                adult_id=adult_id,
                encryption_public_key=_decode_key(payload.device_keys.encryption_public_key),
                signing_public_key=_decode_key(payload.device_keys.signing_public_key),
                state="active",
                last_sync_sequence=0,
                created_at=now,
                revoked_at=None,
            )
        )
        return _new_session(connection, adult_id, device_id)


@router.post("/authentication/options", response_model=CeremonyOptions)
def authentication_options(request: Request) -> CeremonyOptions:
    challenge_id = uuid4()
    challenge = secrets.token_bytes(32)
    verifier: WebAuthnVerifier = request.app.state.webauthn
    database: TransactionalDatabase = request.app.state.database
    with database.transaction() as connection:
        connection.execute(
            challenges.insert().values(
                id=challenge_id,
                kind="authentication",
                challenge=challenge,
                prospective_adult_id=None,
                expires_at=datetime.now(UTC) + timedelta(minutes=5),
                consumed_at=None,
                created_at=datetime.now(UTC),
            )
        )
    return CeremonyOptions(
        challenge_id=challenge_id,
        public_key=verifier.authentication_options(challenge=challenge),
    )


@router.post("/authentication/complete", response_model=SessionResponse)
def authentication_complete(payload: CeremonyCompletion, request: Request) -> SessionResponse:
    """Replace the active phone atomically, advancing accessible resource epochs.

    Fresh authorized-device grants are required for future writes. Authentication
    never returns resource keys or decrypts an encrypted recovery snapshot.
    """
    verifier: WebAuthnVerifier = request.app.state.webauthn
    database: TransactionalDatabase = request.app.state.database
    try:
        credential_id = base64url_to_bytes(str(payload.credential["id"]))
    except (KeyError, TypeError, ValueError) as error:
        raise InvalidCredential from error
    with database.transaction() as connection:
        challenge, _ = _consume_challenge(connection, payload.challenge_id, "authentication")
        credential = (
            connection.execute(
                select(credentials)
                .where(credentials.c.credential_id == credential_id)
                .with_for_update()
            )
            .mappings()
            .one_or_none()
        )
        if credential is None:
            raise InvalidCredential
        try:
            verified = verifier.verify_authentication(
                credential=payload.credential,
                challenge=challenge,
                credential_public_key=credential["public_key"],
                current_sign_count=credential["sign_count"],
            )
        except Exception as error:
            raise InvalidCredential from error
        adult_id: UUID = credential["adult_id"]
        # Serialize replacement across every passkey belonging to this adult.
        connection.execute(select(adults.c.id).where(adults.c.id == adult_id).with_for_update())
        replacing = connection.execute(
            select(devices.c.id).where(
                and_(devices.c.adult_id == adult_id, devices.c.state == "active")
            )
        ).first()
        if replacing is not None:
            advance_replacement_epochs(connection, adult_id)
        now = datetime.now(UTC)
        connection.execute(
            update(credentials)
            .where(credentials.c.credential_id == credential_id)
            .values(sign_count=verified.new_sign_count)
        )
        connection.execute(
            update(devices)
            .where(and_(devices.c.adult_id == adult_id, devices.c.state == "active"))
            .values(state="revoked", revoked_at=now)
        )
        connection.execute(
            update(sessions)
            .where(and_(sessions.c.adult_id == adult_id, sessions.c.revoked_at.is_(None)))
            .values(revoked_at=now)
        )
        device_id = uuid4()
        connection.execute(
            devices.insert().values(
                id=device_id,
                adult_id=adult_id,
                encryption_public_key=_decode_key(payload.device_keys.encryption_public_key),
                signing_public_key=_decode_key(payload.device_keys.signing_public_key),
                state="active",
                last_sync_sequence=0,
                created_at=now,
                revoked_at=None,
            )
        )
        return _new_session(connection, adult_id, device_id)
