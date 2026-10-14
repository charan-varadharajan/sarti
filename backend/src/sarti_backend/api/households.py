import base64
import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal, Protocol
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import Connection, and_, delete, func, select, update

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import ConflictDetected, PermissionDenied, TenantAccessDenied
from sarti_backend.db.schema import (
    adults,
    devices,
    families,
    invitations,
    memberships,
    permissions,
    resources,
    sync_operations,
)
from sarti_backend.households.authorization import require_active_member, require_owner


class TransactionalDatabase(Protocol):
    def transaction(self) -> Any: ...

    def connect(self) -> Any: ...


class ResourceResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    kind: Literal[
        "family_profile", "child_profile", "calendar", "personal_calendar", "participant_profile"
    ]
    key_epoch: int
    permission: Literal["read", "write", "admin"] | None = None


class FamilyResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    role: Literal["owner", "guardian"]
    status: Literal["pending", "active", "revoked"]
    resources: list[ResourceResponse]
    sync_start_cursor: int = 0


class FamilyCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    family_id: UUID | None = None
    calendar_resource_id: UUID | None = None

    @model_validator(mode="after")
    def require_complete_offline_identity(self) -> "FamilyCreate":
        if (self.family_id is None) != (self.calendar_resource_id is None):
            raise ValueError("family_id and calendar_resource_id must be supplied together")
        return self


class ResourceCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["child_profile", "personal_calendar", "participant_profile"]
    resource_id: UUID | None = None
    share_with_calendar_guardians: bool = False


class InvitationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    token: str
    expires_at: datetime


class InvitationAccept(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str


class InvitationAccepted(BaseModel):
    model_config = ConfigDict(extra="forbid")

    invitation_id: UUID
    family_id: UUID
    status: Literal["pending"]


class PermissionAssignment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    resource_id: UUID
    permission: Literal["read", "write", "admin"]


class InvitationReview(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: UUID
    status: str
    expires_at: datetime
    adult_id: UUID | None = None
    device_id: UUID | None = None
    encryption_public_key: str | None = None
    signing_public_key: str | None = None
    member_status: str | None = None
    permissions: dict[UUID, str] = Field(default_factory=dict)


class InvitationApproval(BaseModel):
    model_config = ConfigDict(extra="forbid")

    permissions: list[PermissionAssignment]
    expected_device_id: UUID | None = None
    expected_key_digest: str | None = Field(default=None, pattern="^[0-9a-f]{64}$")


class MembershipResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    adult_id: UUID
    family_id: UUID
    status: Literal["active", "revoked"]
    new_key_epoch: int | None = None


router = APIRouter(prefix="/v1", tags=["households"])
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]


def _lock_active_actor(connection: Connection, actor: AuthenticatedDevice) -> None:
    connection.execute(select(adults.c.id).where(adults.c.id == actor.adult_id).with_for_update())
    if (
        connection.execute(
            select(devices.c.id).where(
                and_(devices.c.id == actor.device_id, devices.c.state == "active")
            )
        ).first()
        is None
    ):
        raise PermissionDenied


@router.post("/families", response_model=FamilyResponse, status_code=201)
def create_family(
    request: Request, actor: Authenticated, payload: FamilyCreate | None = None
) -> FamilyResponse:
    database: TransactionalDatabase = request.app.state.database
    requested = payload or FamilyCreate()
    family_id = requested.family_id or uuid4()
    profile_id = uuid4()
    calendar_id = requested.calendar_resource_id or uuid4()
    now = datetime.now(UTC)
    with database.transaction() as connection:
        existing_family = connection.execute(
            select(families.c.created_by).where(families.c.id == family_id)
        ).one_or_none()
        if existing_family is not None:
            if existing_family.created_by != actor.adult_id:
                raise ConflictDetected("The offline family identifier is unavailable.")
            existing_resources = connection.execute(
                select(
                    resources.c.id,
                    resources.c.kind,
                    resources.c.key_epoch,
                    resources.c.private_adult_id,
                ).where(and_(resources.c.family_id == family_id, resources.c.deleted_at.is_(None)))
            ).all()
            if not any(
                row.id == calendar_id and row.kind == "calendar"
                for row in existing_resources
                if row.private_adult_id is None or row.private_adult_id == actor.adult_id
            ):
                raise ConflictDetected("The offline family identity does not match.")
            return FamilyResponse(
                id=family_id,
                role="owner",
                status="active",
                resources=[
                    ResourceResponse(id=row.id, kind=row.kind, key_epoch=row.key_epoch)
                    for row in existing_resources
                    if row.private_adult_id is None or row.private_adult_id == actor.adult_id
                ],
            )
        identifier_in_use = connection.execute(
            select(resources.c.id).where(resources.c.id.in_((family_id, calendar_id)))
        ).first()
        if identifier_in_use is not None:
            raise ConflictDetected("The offline family identifier is unavailable.")
        connection.execute(
            families.insert().values(
                id=family_id,
                created_by=actor.adult_id,
                created_at=now,
                deleted_at=None,
            )
        )
        connection.execute(
            memberships.insert().values(
                family_id=family_id,
                adult_id=actor.adult_id,
                role="owner",
                status="active",
                created_at=now,
                revoked_at=None,
            )
        )
        connection.execute(
            resources.insert(),
            [
                {
                    "id": profile_id,
                    "family_id": family_id,
                    "kind": "family_profile",
                    "key_epoch": 1,
                    "created_at": now,
                    "deleted_at": None,
                },
                {
                    "id": calendar_id,
                    "family_id": family_id,
                    "kind": "calendar",
                    "key_epoch": 1,
                    "created_at": now,
                    "deleted_at": None,
                },
            ],
        )
    return FamilyResponse(
        id=family_id,
        role="owner",
        status="active",
        resources=[
            ResourceResponse(id=profile_id, kind="family_profile", key_epoch=1),
            ResourceResponse(id=calendar_id, kind="calendar", key_epoch=1),
        ],
    )


@router.get("/families", response_model=list[FamilyResponse])
def list_families(request: Request, actor: Authenticated) -> list[FamilyResponse]:
    database: TransactionalDatabase = request.app.state.database
    with database.connect() as connection:
        member_rows = connection.execute(
            select(
                memberships.c.family_id,
                memberships.c.role,
                memberships.c.status,
                memberships.c.sync_start_cursor,
            ).where(
                and_(memberships.c.adult_id == actor.adult_id, memberships.c.status != "revoked")
            )
        ).all()
        result: list[FamilyResponse] = []
        for membership in member_rows:
            allowed = dict(
                connection.execute(
                    select(permissions.c.resource_id, permissions.c.permission).where(
                        permissions.c.adult_id == actor.adult_id
                    )
                ).all()
            )
            resource_rows = connection.execute(
                select(
                    resources.c.id,
                    resources.c.kind,
                    resources.c.key_epoch,
                    resources.c.private_adult_id,
                ).where(
                    and_(
                        resources.c.family_id == membership.family_id,
                        resources.c.deleted_at.is_(None),
                    )
                )
            ).all()
            result.append(
                FamilyResponse(
                    id=membership.family_id,
                    role=membership.role,
                    status=membership.status,
                    sync_start_cursor=membership.sync_start_cursor,
                    resources=[
                        ResourceResponse(
                            id=row.id,
                            kind=row.kind,
                            key_epoch=row.key_epoch,
                            permission="admin"
                            if membership.role == "owner" or row.private_adult_id == actor.adult_id
                            else allowed[row.id],
                        )
                        for row in resource_rows
                        if membership.status == "active"
                        and (
                            row.private_adult_id == actor.adult_id
                            or (
                                row.private_adult_id is None
                                and (membership.role == "owner" or row.id in allowed)
                            )
                        )
                    ],
                )
            )
    return result


@router.post(
    "/families/{family_id}/resources",
    response_model=ResourceResponse,
    status_code=201,
    response_model_exclude_none=True,
)
def create_resource(
    family_id: UUID,
    payload: ResourceCreate,
    request: Request,
    actor: Authenticated,
) -> ResourceResponse:
    database: TransactionalDatabase = request.app.state.database
    resource_id = payload.resource_id or uuid4()
    with database.transaction() as connection:
        if payload.kind in {"personal_calendar", "participant_profile"}:
            require_active_member(connection, family_id, actor.adult_id)
            if payload.kind == "personal_calendar" and payload.share_with_calendar_guardians:
                raise PermissionDenied
        else:
            require_owner(connection, family_id, actor.adult_id)
        connection.execute(
            select(families.c.id).where(families.c.id == family_id).with_for_update()
        )
        if payload.kind == "personal_calendar":
            current = connection.execute(
                select(resources.c.id).where(
                    and_(
                        resources.c.family_id == family_id,
                        resources.c.private_adult_id == actor.adult_id,
                        resources.c.deleted_at.is_(None),
                    )
                )
            ).scalar_one_or_none()
            if current is not None and current != resource_id:
                raise ConflictDetected("Receive the existing personal resource before publishing.")
        existing = (
            connection.execute(select(resources).where(resources.c.id == resource_id))
            .mappings()
            .one_or_none()
        )
        if existing is not None:
            if (
                existing["family_id"] != family_id
                or existing["kind"] != payload.kind
                or existing["deleted_at"] is not None
                or (
                    payload.kind == "personal_calendar"
                    and existing["private_adult_id"] != actor.adult_id
                )
            ):
                raise ConflictDetected()
            return ResourceResponse(
                id=resource_id, kind=payload.kind, key_epoch=existing["key_epoch"]
            )
        connection.execute(
            resources.insert().values(
                id=resource_id,
                family_id=family_id,
                kind=payload.kind,
                private_adult_id=actor.adult_id if payload.kind == "personal_calendar" else None,
                key_epoch=1,
                created_at=datetime.now(UTC),
                deleted_at=None,
            )
        )
        if payload.kind == "participant_profile":
            connection.execute(
                permissions.insert().values(
                    resource_id=resource_id, adult_id=actor.adult_id, permission="admin"
                )
            )
        if payload.share_with_calendar_guardians:
            # Explicit owner choice applies only at initial provisioning. A
            # retry must never expand access to guardians who joined later.
            recipients = connection.execute(
                select(memberships.c.adult_id)
                .join(permissions, permissions.c.adult_id == memberships.c.adult_id)
                .join(resources, resources.c.id == permissions.c.resource_id)
                .where(
                    and_(
                        memberships.c.family_id == family_id,
                        memberships.c.status == "active",
                        memberships.c.role == "guardian",
                        memberships.c.adult_id != actor.adult_id,
                        resources.c.family_id == family_id,
                        resources.c.kind == "calendar",
                        resources.c.deleted_at.is_(None),
                    )
                )
                .distinct()
            ).scalars()
            for adult_id in recipients:
                connection.execute(
                    permissions.insert().values(
                        resource_id=resource_id, adult_id=adult_id, permission="read"
                    )
                )
    return ResourceResponse(id=resource_id, kind=payload.kind, key_epoch=1)


@router.post(
    "/families/{family_id}/invitations", response_model=InvitationResponse, status_code=201
)
def create_invitation(
    family_id: UUID, request: Request, actor: Authenticated
) -> InvitationResponse:
    database: TransactionalDatabase = request.app.state.database
    invitation_id = uuid4()
    token = secrets.token_urlsafe(32)
    expires_at = datetime.now(UTC) + timedelta(hours=48)
    with database.transaction() as connection:
        require_owner(connection, family_id, actor.adult_id)
        connection.execute(
            select(families.c.id).where(families.c.id == family_id).with_for_update()
        )
        _lock_active_actor(connection, actor)
        open_invitations = connection.execute(
            select(func.count())
            .select_from(invitations)
            .where(
                and_(
                    invitations.c.family_id == family_id,
                    invitations.c.status.in_(("open", "pending")),
                    invitations.c.expires_at > datetime.now(UTC),
                )
            )
        ).scalar_one()
        if open_invitations >= 5:
            raise ConflictDetected("Too many active invitations.")
        connection.execute(
            invitations.insert().values(
                id=invitation_id,
                family_id=family_id,
                inviter_adult_id=actor.adult_id,
                token_digest=hashlib.sha256(token.encode("ascii")).digest(),
                status="open",
                accepted_by=None,
                expires_at=expires_at,
                created_at=datetime.now(UTC),
                used_at=None,
            )
        )
    return InvitationResponse(id=invitation_id, token=token, expires_at=expires_at)


@router.post("/invitations/accept", response_model=InvitationAccepted)
def accept_invitation(
    payload: InvitationAccept, request: Request, actor: Authenticated
) -> InvitationAccepted:
    if len(payload.token) < 32 or len(payload.token) > 256 or not payload.token.isascii():
        raise TenantAccessDenied
    database: TransactionalDatabase = request.app.state.database
    digest = hashlib.sha256(payload.token.encode("ascii")).digest()
    with database.transaction() as connection:
        invitation = (
            connection.execute(select(invitations).where(invitations.c.token_digest == digest))
            .mappings()
            .one_or_none()
        )
        if invitation is None:
            raise TenantAccessDenied
        connection.execute(
            select(families.c.id).where(families.c.id == invitation["family_id"]).with_for_update()
        )
        _lock_active_actor(connection, actor)
        invitation = (
            connection.execute(
                select(invitations).where(invitations.c.token_digest == digest).with_for_update()
            )
            .mappings()
            .one()
        )
        if (
            invitation is None
            or invitation["status"] != "open"
            or invitation["expires_at"] <= datetime.now(UTC)
            or invitation["inviter_adult_id"] == actor.adult_id
        ):
            raise TenantAccessDenied
        existing = connection.execute(
            select(memberships.c.status).where(
                and_(
                    memberships.c.family_id == invitation["family_id"],
                    memberships.c.adult_id == actor.adult_id,
                )
            )
        ).scalar_one_or_none()
        if existing == "active":
            raise ConflictDetected("A membership already exists for this family.")
        if existing == "pending":
            live_pending = connection.execute(
                select(invitations.c.id).where(
                    and_(
                        invitations.c.family_id == invitation["family_id"],
                        invitations.c.accepted_by == actor.adult_id,
                        invitations.c.status == "pending",
                        invitations.c.expires_at > datetime.now(UTC),
                    )
                )
            ).first()
            if live_pending is not None:
                raise ConflictDetected("An invitation is already awaiting approval.")
        if existing == "pending":
            connection.execute(
                update(invitations)
                .where(
                    and_(
                        invitations.c.family_id == invitation["family_id"],
                        invitations.c.accepted_by == actor.adult_id,
                        invitations.c.status == "pending",
                        invitations.c.expires_at <= datetime.now(UTC),
                    )
                )
                .values(status="revoked")
            )
        if existing is not None:
            connection.execute(
                update(memberships)
                .where(
                    and_(
                        memberships.c.family_id == invitation["family_id"],
                        memberships.c.adult_id == actor.adult_id,
                    )
                )
                .values(status="pending", revoked_at=None, sync_start_cursor=0)
            )
        else:
            connection.execute(
                memberships.insert().values(
                    family_id=invitation["family_id"],
                    adult_id=actor.adult_id,
                    role="guardian",
                    status="pending",
                    created_at=datetime.now(UTC),
                    revoked_at=None,
                )
            )
        connection.execute(
            update(invitations)
            .where(invitations.c.id == invitation["id"])
            .values(status="pending", accepted_by=actor.adult_id, used_at=datetime.now(UTC))
        )
        return InvitationAccepted(
            invitation_id=invitation["id"],
            family_id=invitation["family_id"],
            status="pending",
        )


@router.get("/families/{family_id}/invitations", response_model=list[InvitationReview])
def list_invitations(
    family_id: UUID, request: Request, actor: Authenticated
) -> list[InvitationReview]:
    database: TransactionalDatabase = request.app.state.database
    with database.connect() as connection:
        require_owner(connection, family_id, actor.adult_id)
        rows = connection.execute(
            select(invitations)
            .where(invitations.c.family_id == family_id)
            .order_by(invitations.c.created_at.desc())
            .limit(100)
        ).mappings()
        result = []
        for row in rows:
            device = None
            member_status = None
            if row["accepted_by"] is not None:
                device = (
                    connection.execute(
                        select(devices).where(
                            and_(
                                devices.c.adult_id == row["accepted_by"],
                                devices.c.state == "active",
                            )
                        )
                    )
                    .mappings()
                    .one_or_none()
                )
                member_status = connection.execute(
                    select(memberships.c.status).where(
                        and_(
                            memberships.c.family_id == family_id,
                            memberships.c.adult_id == row["accepted_by"],
                        )
                    )
                ).scalar_one_or_none()
            result.append(
                InvitationReview(
                    id=row["id"],
                    status=row["status"],
                    expires_at=row["expires_at"],
                    adult_id=row["accepted_by"],
                    device_id=device["id"] if device else None,
                    member_status=member_status,
                    permissions=dict(
                        connection.execute(
                            select(permissions.c.resource_id, permissions.c.permission)
                            .join(resources, resources.c.id == permissions.c.resource_id)
                            .where(
                                and_(
                                    permissions.c.adult_id == row["accepted_by"],
                                    resources.c.family_id == family_id,
                                )
                            )
                        ).all()
                    )
                    if row["accepted_by"] is not None
                    else {},
                    encryption_public_key=base64.urlsafe_b64encode(device["encryption_public_key"])
                    .decode()
                    .rstrip("=")
                    if device
                    else None,
                    signing_public_key=base64.urlsafe_b64encode(device["signing_public_key"])
                    .decode()
                    .rstrip("=")
                    if device
                    else None,
                )
            )
        return result


@router.delete("/families/{family_id}/invitations/{invitation_id}", status_code=204)
def cancel_invitation(
    family_id: UUID, invitation_id: UUID, request: Request, actor: Authenticated
) -> Response:
    database: TransactionalDatabase = request.app.state.database
    with database.transaction() as connection:
        require_owner(connection, family_id, actor.adult_id)
        connection.execute(
            select(families.c.id).where(families.c.id == family_id).with_for_update()
        )
        _lock_active_actor(connection, actor)
        row = (
            connection.execute(
                select(invitations)
                .where(
                    and_(invitations.c.id == invitation_id, invitations.c.family_id == family_id)
                )
                .with_for_update()
            )
            .mappings()
            .one_or_none()
        )
        if row is None or row["status"] == "approved":
            raise ConflictDetected("This invitation cannot be cancelled.")
        if row["status"] == "revoked":
            return Response(status_code=204)
        connection.execute(
            update(invitations).where(invitations.c.id == invitation_id).values(status="revoked")
        )
        if row["accepted_by"] is not None:
            connection.execute(
                update(memberships)
                .where(
                    and_(
                        memberships.c.family_id == family_id,
                        memberships.c.adult_id == row["accepted_by"],
                        memberships.c.status == "pending",
                    )
                )
                .values(status="revoked", revoked_at=datetime.now(UTC))
            )
    return Response(status_code=204)


@router.post(
    "/families/{family_id}/invitations/{invitation_id}/approve", response_model=MembershipResponse
)
def approve_invitation(
    family_id: UUID,
    invitation_id: UUID,
    payload: InvitationApproval,
    request: Request,
    actor: Authenticated,
) -> MembershipResponse:
    database: TransactionalDatabase = request.app.state.database
    with database.transaction() as connection:
        require_owner(connection, family_id, actor.adult_id)
        connection.execute(
            select(families.c.id).where(families.c.id == family_id).with_for_update()
        )
        invitation = (
            connection.execute(
                select(invitations)
                .where(
                    and_(invitations.c.id == invitation_id, invitations.c.family_id == family_id)
                )
                .with_for_update()
            )
            .mappings()
            .one_or_none()
        )
        if (
            invitation is None
            or invitation["accepted_by"] is None
            or invitation["status"] not in ("pending", "approved")
        ):
            raise ConflictDetected("The invitation is not awaiting approval.")
        recipient_id = invitation["accepted_by"]
        # Same adult-before-resource ordering as device replacement. A pending
        # recipient cannot replace its phone halfway through approval/pinning.
        connection.execute(
            select(adults.c.id)
            .where(adults.c.id.in_((actor.adult_id, recipient_id)))
            .order_by(adults.c.id)
            .with_for_update()
        ).all()
        allowed = set(
            connection.execute(
                select(resources.c.id)
                .where(
                    and_(
                        resources.c.family_id == family_id,
                        resources.c.deleted_at.is_(None),
                        resources.c.private_adult_id.is_(None),
                    )
                )
                .order_by(resources.c.id)
                .with_for_update()
            ).scalars()
        )
        requested = {p.resource_id: p.permission for p in payload.permissions}
        if (
            not requested
            or len(requested) != len(payload.permissions)
            or not set(requested).issubset(allowed)
        ):
            raise PermissionDenied
        if (
            connection.execute(
                select(devices.c.id).where(
                    and_(devices.c.id == actor.device_id, devices.c.state == "active")
                )
            ).first()
            is None
        ):
            raise PermissionDenied
        recipient = (
            connection.execute(
                select(devices).where(
                    and_(devices.c.adult_id == recipient_id, devices.c.state == "active")
                )
            )
            .mappings()
            .one_or_none()
        )
        if recipient is None:
            raise ConflictDetected("The guardian must authenticate on an active phone.")
        digest = hashlib.sha256(
            recipient["signing_public_key"] + recipient["encryption_public_key"]
        ).hexdigest()
        if (
            payload.expected_device_id is not None and payload.expected_device_id != recipient["id"]
        ) or (
            payload.expected_key_digest is not None
            and not secrets.compare_digest(payload.expected_key_digest, digest)
        ):
            raise ConflictDetected(
                "The guardian device changed. Review its verification code again."
            )
        status = connection.execute(
            select(memberships.c.status).where(
                and_(memberships.c.family_id == family_id, memberships.c.adult_id == recipient_id)
            )
        ).scalar_one_or_none()
        if invitation["status"] == "approved":
            current = dict(
                connection.execute(
                    select(permissions.c.resource_id, permissions.c.permission).where(
                        and_(
                            permissions.c.adult_id == recipient_id,
                            permissions.c.resource_id.in_(allowed),
                        )
                    )
                ).all()
            )
            if status != "active" or current != requested:
                raise ConflictDetected("Approval no longer matches this guardian's access.")
            return MembershipResponse(adult_id=recipient_id, family_id=family_id, status="active")
        if invitation["expires_at"] <= datetime.now(UTC) or status != "pending":
            raise ConflictDetected("The invitation expired or is no longer pending.")
        floor = connection.execute(
            select(func.coalesce(func.max(sync_operations.c.server_sequence), 0))
        ).scalar_one()
        connection.execute(
            update(memberships)
            .where(
                and_(memberships.c.family_id == family_id, memberships.c.adult_id == recipient_id)
            )
            .values(status="active", sync_start_cursor=floor)
        )
        connection.execute(
            permissions.insert(),
            [
                {"resource_id": r, "adult_id": recipient_id, "permission": permission}
                for r, permission in requested.items()
            ],
        )
        connection.execute(
            update(invitations).where(invitations.c.id == invitation_id).values(status="approved")
        )
        return MembershipResponse(adult_id=recipient_id, family_id=family_id, status="active")


@router.delete("/families/{family_id}/guardians/{guardian_id}", response_model=MembershipResponse)
def revoke_guardian(
    family_id: UUID, guardian_id: UUID, request: Request, actor: Authenticated
) -> MembershipResponse:
    database: TransactionalDatabase = request.app.state.database
    now = datetime.now(UTC)
    with database.transaction() as connection:
        require_owner(connection, family_id, actor.adult_id)
        connection.execute(
            select(families.c.id).where(families.c.id == family_id).with_for_update()
        )
        _lock_active_actor(connection, actor)
        connection.execute(
            select(resources.c.id)
            .where(resources.c.family_id == family_id)
            .order_by(resources.c.id)
            .with_for_update()
        ).all()
        changed = connection.execute(
            update(memberships)
            .where(
                and_(
                    memberships.c.family_id == family_id,
                    memberships.c.adult_id == guardian_id,
                    memberships.c.role == "guardian",
                    memberships.c.status == "active",
                )
            )
            .values(status="revoked", revoked_at=now)
        )
        if changed.rowcount != 1:
            raise TenantAccessDenied
        connection.execute(
            update(invitations)
            .where(
                and_(
                    invitations.c.family_id == family_id,
                    invitations.c.accepted_by == guardian_id,
                    invitations.c.status.in_(("pending", "approved")),
                )
            )
            .values(status="revoked")
        )
        resource_ids = select(resources.c.id).where(resources.c.family_id == family_id)
        connection.execute(
            delete(permissions).where(
                and_(
                    permissions.c.adult_id == guardian_id,
                    permissions.c.resource_id.in_(resource_ids),
                )
            )
        )
        epochs = (
            connection.execute(
                update(resources)
                .where(
                    and_(
                        resources.c.family_id == family_id,
                        resources.c.deleted_at.is_(None),
                        resources.c.private_adult_id.is_(None),
                    )
                )
                .values(key_epoch=resources.c.key_epoch + 1)
                .returning(resources.c.key_epoch)
            )
            .scalars()
            .all()
        )
        return MembershipResponse(
            adult_id=guardian_id,
            family_id=family_id,
            status="revoked",
            new_key_epoch=max(epochs) if epochs else None,
        )
