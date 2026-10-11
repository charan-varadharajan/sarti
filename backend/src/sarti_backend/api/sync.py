import base64
import binascii
import hashlib
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Protocol
from uuid import UUID, uuid4

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import and_, select, update

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import (
    ConflictDetected,
    InvalidRequest,
    PermissionDenied,
    TenantAccessDenied,
)
from sarti_backend.db.schema import devices, key_grants, memberships, sync_operations
from sarti_backend.households.authorization import require_active_member, require_resource_permission
from sarti_backend.sync.retention import delete_expired_operations


class TransactionalDatabase(Protocol):
    def transaction(self) -> Any: ...

    def connect(self) -> Any: ...


def _decode(value: str, expected_size: int | None = None) -> bytes:
    try:
        result = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except (ValueError, binascii.Error) as error:
        raise InvalidRequest from error
    if expected_size is not None and len(result) != expected_size:
        raise InvalidRequest
    return result


def _encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


class OperationUpload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    operation_id: UUID
    family_id: UUID
    resource_id: UUID
    device_sequence: int = Field(gt=0)
    key_epoch: int = Field(gt=0)
    logical_version: dict[str, int]
    nonce: str = Field(min_length=32, max_length=32)
    ciphertext: str = Field(min_length=23, max_length=1_398_124)
    content_digest: str = Field(min_length=43, max_length=44)

    @field_validator("logical_version")
    @classmethod
    def validate_version(cls, value: dict[str, int]) -> dict[str, int]:
        if not value or len(value) > 16:
            raise ValueError("logical version must contain 1-16 devices")
        for key, counter in value.items():
            UUID(key)
            if counter < 0 or counter > 2**63 - 1:
                raise ValueError("invalid logical version counter")
        return value


class OperationReceipt(BaseModel):
    model_config = ConfigDict(extra="forbid")

    operation_id: UUID
    server_sequence: int
    duplicate: bool
    expires_at: datetime


class RelayOperation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    server_sequence: int
    operation_id: UUID
    family_id: UUID
    resource_id: UUID
    author_device_id: UUID
    device_sequence: int
    key_epoch: int
    logical_version: dict[str, int]
    nonce: str
    ciphertext: str
    content_digest: str
    expires_at: datetime


class RelayPage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    operations: list[RelayOperation]
    next_cursor: int


class KeyGrantUpload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    family_id: UUID
    resource_id: UUID
    key_epoch: int = Field(gt=0)
    recipient_device_id: UUID
    wrapped_key: str = Field(min_length=64, max_length=684)
    signature: str = Field(min_length=86, max_length=88)


class KeyGrantResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    resource_id: UUID
    key_epoch: int
    recipient_device_id: UUID
    granter_device_id: UUID
    wrapped_key: str
    signature: str


router = APIRouter(prefix="/v1", tags=["encrypted-sync"])
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]


def _grant_message(
    resource_id: UUID,
    key_epoch: int,
    recipient_device_id: UUID,
    granter_device_id: UUID,
    wrapped_key: bytes,
) -> bytes:
    return b"".join(
        (
            b"SARTI-GRANT-V1\0",
            resource_id.bytes,
            key_epoch.to_bytes(8, "big"),
            recipient_device_id.bytes,
            granter_device_id.bytes,
            hashlib.sha256(wrapped_key).digest(),
        )
    )


@router.post("/sync/operations", response_model=OperationReceipt, status_code=201)
def upload_operation(
    payload: OperationUpload, request: Request, actor: Authenticated
) -> OperationReceipt:
    database: TransactionalDatabase = request.app.state.database
    nonce = _decode(payload.nonce, 24)
    ciphertext = _decode(payload.ciphertext)
    digest = _decode(payload.content_digest, 32)
    if len(ciphertext) < 17 or len(ciphertext) > 1_048_592:
        raise InvalidRequest
    if not hashlib.sha256(nonce + ciphertext).digest() == digest:
        raise ConflictDetected("The ciphertext digest does not match the envelope.")
    now = datetime.now(UTC)
    with database.transaction() as connection:
        delete_expired_operations(connection, now)
        existing = (
            connection.execute(
                select(sync_operations).where(
                    sync_operations.c.operation_id == payload.operation_id
                )
            )
            .mappings()
            .one_or_none()
        )
        if existing is not None:
            if (
                existing["author_device_id"] == actor.device_id
                and existing["content_digest"] == digest
                and existing["device_sequence"] == payload.device_sequence
            ):
                return OperationReceipt(
                    operation_id=payload.operation_id,
                    server_sequence=existing["server_sequence"],
                    duplicate=True,
                    expires_at=existing["expires_at"],
                )
            raise ConflictDetected("The operation identifier was already used.")
        device = connection.execute(
            select(devices.c.last_sync_sequence)
            .where(and_(devices.c.id == actor.device_id, devices.c.state == "active"))
            .with_for_update()
        ).one_or_none()
        if device is None:
            raise TenantAccessDenied
        expected_sequence = int(device.last_sync_sequence) + 1
        if payload.device_sequence != expected_sequence:
            raise ConflictDetected("The device sequence is missing, duplicated, or replayed.")
        epoch, _ = require_resource_permission(
            connection,
            family_id=payload.family_id,
            resource_id=payload.resource_id,
            adult_id=actor.adult_id,
            required="write",
        )
        if payload.key_epoch != epoch:
            raise ConflictDetected("The operation uses a stale resource key epoch.")
        expires_at = now + timedelta(days=7)
        server_sequence = connection.execute(
            sync_operations.insert()
            .values(
                operation_id=payload.operation_id,
                family_id=payload.family_id,
                resource_id=payload.resource_id,
                author_device_id=actor.device_id,
                device_sequence=payload.device_sequence,
                key_epoch=payload.key_epoch,
                logical_version=payload.logical_version,
                nonce=nonce,
                ciphertext=ciphertext,
                content_digest=digest,
                received_at=now,
                expires_at=expires_at,
            )
            .returning(sync_operations.c.server_sequence)
        ).scalar_one()
        connection.execute(
            update(devices)
            .where(devices.c.id == actor.device_id)
            .values(last_sync_sequence=payload.device_sequence)
        )
    return OperationReceipt(
        operation_id=payload.operation_id,
        server_sequence=server_sequence,
        duplicate=False,
        expires_at=expires_at,
    )


@router.get("/families/{family_id}/sync", response_model=RelayPage)
def download_operations(
    family_id: UUID,
    request: Request,
    actor: Authenticated,
    cursor: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
) -> RelayPage:
    database: TransactionalDatabase = request.app.state.database
    now = datetime.now(UTC)
    operations: list[RelayOperation] = []
    with database.connect() as connection:
        require_active_member(connection, family_id, actor.adult_id)
        rows = connection.execute(
            select(sync_operations)
            .where(
                and_(
                    sync_operations.c.family_id == family_id,
                    sync_operations.c.server_sequence > cursor,
                    sync_operations.c.expires_at > now,
                )
            )
            .order_by(sync_operations.c.server_sequence)
            .limit(limit)
        ).mappings()
        for row in rows:
            require_resource_permission(
                connection,
                family_id=family_id,
                resource_id=row["resource_id"],
                adult_id=actor.adult_id,
                required="read",
            )
            operations.append(
                RelayOperation(
                    server_sequence=row["server_sequence"],
                    operation_id=row["operation_id"],
                    family_id=row["family_id"],
                    resource_id=row["resource_id"],
                    author_device_id=row["author_device_id"],
                    device_sequence=row["device_sequence"],
                    key_epoch=row["key_epoch"],
                    logical_version=row["logical_version"],
                    nonce=_encode(row["nonce"]),
                    ciphertext=_encode(row["ciphertext"]),
                    content_digest=_encode(row["content_digest"]),
                    expires_at=row["expires_at"],
                )
            )
    return RelayPage(
        operations=operations,
        next_cursor=operations[-1].server_sequence if operations else cursor,
    )


@router.post("/key-grants", response_model=KeyGrantResponse, status_code=201)
def create_key_grant(
    payload: KeyGrantUpload, request: Request, actor: Authenticated
) -> KeyGrantResponse:
    database: TransactionalDatabase = request.app.state.database
    wrapped_key = _decode(payload.wrapped_key)
    signature = _decode(payload.signature, 64)
    if len(wrapped_key) < 48 or len(wrapped_key) > 512:
        raise InvalidRequest
    grant_id = uuid4()
    with database.transaction() as connection:
        epoch, _ = require_resource_permission(
            connection,
            family_id=payload.family_id,
            resource_id=payload.resource_id,
            adult_id=actor.adult_id,
            required="admin",
        )
        if payload.key_epoch != epoch:
            raise ConflictDetected("The key grant uses a stale resource key epoch.")
        recipient = connection.execute(
            select(devices.c.adult_id).where(
                and_(
                    devices.c.id == payload.recipient_device_id,
                    devices.c.state == "active",
                )
            )
        ).one_or_none()
        if recipient is None:
            raise PermissionDenied
        membership = connection.execute(
            select(memberships.c.status).where(
                and_(
                    memberships.c.family_id == payload.family_id,
                    memberships.c.adult_id == recipient.adult_id,
                    memberships.c.status == "active",
                )
            )
        ).one_or_none()
        if membership is None:
            raise PermissionDenied
        require_resource_permission(
            connection,
            family_id=payload.family_id,
            resource_id=payload.resource_id,
            adult_id=recipient.adult_id,
            required="read",
        )
        signing_key = connection.execute(
            select(devices.c.signing_public_key).where(devices.c.id == actor.device_id)
        ).scalar_one()
        try:
            Ed25519PublicKey.from_public_bytes(signing_key).verify(
                signature,
                _grant_message(
                    payload.resource_id,
                    payload.key_epoch,
                    payload.recipient_device_id,
                    actor.device_id,
                    wrapped_key,
                ),
            )
        except (InvalidSignature, ValueError) as error:
            raise PermissionDenied from error
        connection.execute(
            key_grants.insert().values(
                id=grant_id,
                resource_id=payload.resource_id,
                key_epoch=payload.key_epoch,
                recipient_device_id=payload.recipient_device_id,
                granter_device_id=actor.device_id,
                wrapped_key=wrapped_key,
                signature=signature,
                created_at=datetime.now(UTC),
            )
        )
    return KeyGrantResponse(
        id=grant_id,
        resource_id=payload.resource_id,
        key_epoch=payload.key_epoch,
        recipient_device_id=payload.recipient_device_id,
        granter_device_id=actor.device_id,
        wrapped_key=payload.wrapped_key,
        signature=payload.signature,
    )


@router.get("/key-grants", response_model=list[KeyGrantResponse])
def list_key_grants(request: Request, actor: Authenticated) -> list[KeyGrantResponse]:
    database: TransactionalDatabase = request.app.state.database
    with database.connect() as connection:
        rows = connection.execute(
            select(key_grants).where(key_grants.c.recipient_device_id == actor.device_id)
        ).mappings()
        return [
            KeyGrantResponse(
                id=row["id"],
                resource_id=row["resource_id"],
                key_epoch=row["key_epoch"],
                recipient_device_id=row["recipient_device_id"],
                granter_device_id=row["granter_device_id"],
                wrapped_key=_encode(row["wrapped_key"]),
                signature=_encode(row["signature"]),
            )
            for row in rows
        ]
