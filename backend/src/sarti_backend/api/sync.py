import hashlib
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal, Protocol
from uuid import UUID, uuid4

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import and_, select, update

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import (
    ConflictDetected,
    InvalidRequest,
    PermissionDenied,
    TenantAccessDenied,
)
from sarti_backend.db.schema import (
    devices,
    key_grants,
    memberships,
    permissions,
    resources,
    sync_operations,
)
from sarti_backend.households.authorization import (
    require_active_member,
    require_resource_permission,
)
from sarti_backend.sync.envelope import OperationUpload, _decode, _encode
from sarti_backend.sync.retention import delete_expired_operations


class TransactionalDatabase(Protocol):
    def transaction(self) -> Any: ...

    def connect(self) -> Any: ...


class OperationReceipt(BaseModel):
    model_config = ConfigDict(extra="forbid")

    operation_id: UUID
    server_sequence: int
    duplicate: bool
    expires_at: datetime


class RelayOperation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocol_version: Literal[1, 2] = 1
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
    key_epoch: int = Field(gt=0, le=2**31 - 1)
    recipient_device_id: UUID
    wrapped_key: str = Field(min_length=107, max_length=108)
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
        # Same lock order as device replacement: resource, then device.
        connection.execute(
            select(resources.c.id).where(resources.c.id == payload.resource_id).with_for_update()
        )
        delete_expired_operations(connection, now)
        epoch, _ = require_resource_permission(
            connection,
            family_id=payload.family_id,
            resource_id=payload.resource_id,
            adult_id=actor.adult_id,
            required="write",
        )
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
                and existing["family_id"] == payload.family_id
                and existing["resource_id"] == payload.resource_id
                and existing["key_epoch"] == payload.key_epoch
                and existing["logical_version"] == payload.logical_version
                and existing["nonce"] == nonce
                and existing["ciphertext"] == ciphertext
                and existing["protocol_version"] == payload.protocol_version
            ):
                return OperationReceipt(
                    operation_id=payload.operation_id,
                    server_sequence=existing["server_sequence"],
                    duplicate=True,
                    expires_at=existing["expires_at"],
                )
            raise ConflictDetected("The operation identifier was already used.")
        if payload.key_epoch != epoch:
            raise ConflictDetected("The operation uses a stale resource key epoch.")
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
                protocol_version=payload.protocol_version,
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
    next_cursor = cursor
    with database.transaction() as connection:
        delete_expired_operations(connection, now)
        require_active_member(connection, family_id, actor.adult_id)
        floor = connection.execute(
            select(memberships.c.sync_start_cursor).where(
                and_(memberships.c.family_id == family_id, memberships.c.adult_id == actor.adult_id)
            )
        ).scalar_one()
        next_cursor = max(cursor, floor)
        rows = connection.execute(
            select(sync_operations)
            .where(
                and_(
                    sync_operations.c.family_id == family_id,
                    sync_operations.c.server_sequence > next_cursor,
                    sync_operations.c.expires_at > now,
                )
            )
            .order_by(sync_operations.c.server_sequence)
            .limit(limit)
        ).mappings()
        for row in rows:
            next_cursor = row["server_sequence"]
            try:
                require_resource_permission(
                    connection,
                    family_id=family_id,
                    resource_id=row["resource_id"],
                    adult_id=actor.adult_id,
                    required="read",
                )
            except (PermissionDenied, TenantAccessDenied):
                continue
            operations.append(
                RelayOperation(
                    protocol_version=row["protocol_version"],
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
        next_cursor=next_cursor,
    )


@router.post("/key-grants", response_model=KeyGrantResponse, status_code=201)
def create_key_grant(
    payload: KeyGrantUpload, request: Request, actor: Authenticated
) -> KeyGrantResponse:
    database: TransactionalDatabase = request.app.state.database
    wrapped_key = _decode(payload.wrapped_key)
    signature = _decode(payload.signature, 64)
    if len(wrapped_key) != 80:
        raise InvalidRequest
    grant_id = uuid4()
    with database.transaction() as connection:
        connection.execute(
            select(resources.c.id).where(resources.c.id == payload.resource_id).with_for_update()
        )
        epoch, _ = require_resource_permission(
            connection,
            family_id=payload.family_id,
            resource_id=payload.resource_id,
            adult_id=actor.adult_id,
            required="admin",
        )
        if payload.key_epoch != epoch:
            raise ConflictDetected("The key grant uses a stale resource key epoch.")
        active_granter = connection.execute(
            select(devices.c.id).where(
                and_(devices.c.id == actor.device_id, devices.c.state == "active")
            )
        ).first()
        if active_granter is None:
            raise PermissionDenied
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
        existing = (
            connection.execute(
                select(key_grants).where(
                    and_(
                        key_grants.c.resource_id == payload.resource_id,
                        key_grants.c.key_epoch == payload.key_epoch,
                        key_grants.c.recipient_device_id == payload.recipient_device_id,
                    )
                )
            )
            .mappings()
            .one_or_none()
        )
        if existing is not None:
            if (
                existing["granter_device_id"] != actor.device_id
                or existing["wrapped_key"] != wrapped_key
                or existing["signature"] != signature
            ):
                raise ConflictDetected("A grant for this recipient and epoch already exists.")
            return KeyGrantResponse(
                id=existing["id"],
                resource_id=payload.resource_id,
                key_epoch=payload.key_epoch,
                recipient_device_id=payload.recipient_device_id,
                granter_device_id=actor.device_id,
                wrapped_key=payload.wrapped_key,
                signature=payload.signature,
            )
        first_granter = connection.execute(
            select(key_grants.c.granter_device_id)
            .where(
                and_(
                    key_grants.c.resource_id == payload.resource_id,
                    key_grants.c.key_epoch == payload.key_epoch,
                )
            )
            .order_by(key_grants.c.created_at, key_grants.c.id)
            .limit(1)
        ).scalar_one_or_none()
        if first_granter is not None and first_granter != actor.device_id:
            received = connection.execute(
                select(key_grants.c.id)
                .where(
                    and_(
                        key_grants.c.resource_id == payload.resource_id,
                        key_grants.c.key_epoch == payload.key_epoch,
                        key_grants.c.recipient_device_id == actor.device_id,
                        key_grants.c.granter_device_id == first_granter,
                    )
                )
                .limit(1)
            ).first()
            if received is None:
                raise ConflictDetected("Receive the established epoch key before granting it.")
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
            select(key_grants, resources.c.family_id, resources.c.key_epoch.label("current_epoch"))
            .join(resources, resources.c.id == key_grants.c.resource_id)
            .where(key_grants.c.recipient_device_id == actor.device_id)
        ).mappings()
        result = []
        for row in rows:
            if row["key_epoch"] != row["current_epoch"]:
                continue
            granter = connection.execute(
                select(devices.c.adult_id).where(
                    and_(
                        devices.c.id == row["granter_device_id"],
                        devices.c.state == "active",
                    )
                )
            ).scalar_one_or_none()
            if granter is None:
                continue
            try:
                require_resource_permission(
                    connection,
                    family_id=row["family_id"],
                    resource_id=row["resource_id"],
                    adult_id=actor.adult_id,
                    required="read",
                )
                require_resource_permission(
                    connection,
                    family_id=row["family_id"],
                    resource_id=row["resource_id"],
                    adult_id=granter,
                    required="admin",
                )
            except (PermissionDenied, TenantAccessDenied):
                continue
            result.append(
                KeyGrantResponse(
                    id=row["id"],
                    resource_id=row["resource_id"],
                    key_epoch=row["key_epoch"],
                    recipient_device_id=row["recipient_device_id"],
                    granter_device_id=row["granter_device_id"],
                    wrapped_key=_encode(row["wrapped_key"]),
                    signature=_encode(row["signature"]),
                )
            )
        return result


class ResourceDevice(BaseModel):
    model_config = ConfigDict(extra="forbid")
    device_id: UUID
    encryption_public_key: str
    signing_public_key: str
    permission: str
    has_current_grant: bool


@router.get(
    "/families/{family_id}/resources/{resource_id}/devices", response_model=list[ResourceDevice]
)
def list_resource_devices(
    family_id: UUID, resource_id: UUID, request: Request, actor: Authenticated
) -> list[ResourceDevice]:
    database: TransactionalDatabase = request.app.state.database
    with database.connect() as connection:
        epoch, kind = require_resource_permission(
            connection,
            family_id=family_id,
            resource_id=resource_id,
            adult_id=actor.adult_id,
            required="read",
        )
        rows = connection.execute(
            select(devices, memberships.c.role)
            .join(memberships, memberships.c.adult_id == devices.c.adult_id)
            .where(
                and_(
                    memberships.c.family_id == family_id,
                    (
                        memberships.c.expires_at.is_(None)
                        | (memberships.c.expires_at > datetime.now(UTC))
                    ),
                    memberships.c.status == "active",
                    devices.c.state == "active",
                )
            )
        ).mappings()
        result = []
        for row in rows:
            if kind == "personal_calendar" and row["adult_id"] != actor.adult_id:
                continue
            permission = (
                "admin"
                if row["role"] == "owner" or kind == "personal_calendar"
                else connection.execute(
                    select(permissions.c.permission).where(
                        and_(
                            permissions.c.resource_id == resource_id,
                            permissions.c.adult_id == row["adult_id"],
                        )
                    )
                ).scalar_one_or_none()
            )
            if permission is None:
                continue
            has_grant = (
                connection.execute(
                    select(key_grants.c.id)
                    .where(
                        and_(
                            key_grants.c.resource_id == resource_id,
                            key_grants.c.key_epoch == epoch,
                            key_grants.c.recipient_device_id == row["id"],
                        )
                    )
                    .limit(1)
                ).first()
                is not None
            )
            result.append(
                ResourceDevice(
                    device_id=row["id"],
                    encryption_public_key=_encode(row["encryption_public_key"]),
                    signing_public_key=_encode(row["signing_public_key"]),
                    permission=permission,
                    has_current_grant=has_grant,
                )
            )
        return result
