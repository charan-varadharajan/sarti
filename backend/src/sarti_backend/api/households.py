import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal, Protocol
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict, model_validator
from sqlalchemy import and_, delete, func, select, update

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import ConflictDetected, PermissionDenied, TenantAccessDenied
from sarti_backend.db.schema import families, invitations, memberships, permissions, resources
from sarti_backend.households.authorization import require_owner


class TransactionalDatabase(Protocol):
    def transaction(self) -> Any: ...

    def connect(self) -> Any: ...


class ResourceResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    kind: Literal["family_profile", "child_profile", "calendar"]
    key_epoch: int


class FamilyResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    role: Literal["owner", "guardian"]
    status: Literal["pending", "active", "revoked"]
    resources: list[ResourceResponse]


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

    kind: Literal["child_profile"]
    resource_id: UUID | None = None


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


class InvitationApproval(BaseModel):
    model_config = ConfigDict(extra="forbid")

    permissions: list[PermissionAssignment]


class MembershipResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    adult_id: UUID
    family_id: UUID
    status: Literal["active", "revoked"]
    new_key_epoch: int | None = None


router = APIRouter(prefix="/v1", tags=["households"])
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]


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
                select(resources.c.id, resources.c.kind, resources.c.key_epoch).where(
                    and_(resources.c.family_id == family_id, resources.c.deleted_at.is_(None))
                )
            ).all()
            if not any(
                row.id == calendar_id and row.kind == "calendar" for row in existing_resources
            ):
                raise ConflictDetected("The offline family identity does not match.")
            return FamilyResponse(
                id=family_id,
                role="owner",
                status="active",
                resources=[
                    ResourceResponse(id=row.id, kind=row.kind, key_epoch=row.key_epoch)
                    for row in existing_resources
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
            select(memberships.c.family_id, memberships.c.role, memberships.c.status).where(
                and_(memberships.c.adult_id == actor.adult_id, memberships.c.status != "revoked")
            )
        ).all()
        result: list[FamilyResponse] = []
        for membership in member_rows:
            resource_rows = connection.execute(
                select(resources.c.id, resources.c.kind, resources.c.key_epoch).where(
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
                    resources=[
                        ResourceResponse(id=row.id, kind=row.kind, key_epoch=row.key_epoch)
                        for row in resource_rows
                    ],
                )
            )
    return result


@router.post("/families/{family_id}/resources", response_model=ResourceResponse, status_code=201)
def create_resource(
    family_id: UUID,
    payload: ResourceCreate,
    request: Request,
    actor: Authenticated,
) -> ResourceResponse:
    database: TransactionalDatabase = request.app.state.database
    resource_id = payload.resource_id or uuid4()
    with database.transaction() as connection:
        require_owner(connection, family_id, actor.adult_id)
        existing = connection.execute(
            select(resources.c.family_id, resources.c.kind, resources.c.key_epoch).where(
                resources.c.id == resource_id
            )
        ).one_or_none()
        if existing is not None:
            if existing.family_id != family_id or existing.kind != payload.kind:
                raise ConflictDetected("The offline resource identifier is unavailable.")
            return ResourceResponse(
                id=resource_id,
                kind=payload.kind,
                key_epoch=existing.key_epoch,
            )
        connection.execute(
            resources.insert().values(
                id=resource_id,
                family_id=family_id,
                kind=payload.kind,
                key_epoch=1,
                created_at=datetime.now(UTC),
                deleted_at=None,
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
            connection.execute(
                select(invitations).where(invitations.c.token_digest == digest).with_for_update()
            )
            .mappings()
            .one_or_none()
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
        if existing is not None:
            raise ConflictDetected("A membership already exists for this family.")
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


@router.post(
    "/families/{family_id}/invitations/{invitation_id}/approve",
    response_model=MembershipResponse,
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
            or invitation["status"] != "pending"
            or invitation["accepted_by"] is None
        ):
            raise ConflictDetected("The invitation is not awaiting approval.")
        allowed_resources = {
            row.id
            for row in connection.execute(
                select(resources.c.id).where(
                    and_(resources.c.family_id == family_id, resources.c.deleted_at.is_(None))
                )
            )
        }
        requested = {item.resource_id for item in payload.permissions}
        if requested != allowed_resources:
            raise PermissionDenied
        connection.execute(
            update(memberships)
            .where(
                and_(
                    memberships.c.family_id == family_id,
                    memberships.c.adult_id == invitation["accepted_by"],
                    memberships.c.status == "pending",
                )
            )
            .values(status="active")
        )
        connection.execute(
            permissions.insert(),
            [
                {
                    "resource_id": item.resource_id,
                    "adult_id": invitation["accepted_by"],
                    "permission": item.permission,
                }
                for item in payload.permissions
            ],
        )
        connection.execute(
            update(invitations).where(invitations.c.id == invitation_id).values(status="approved")
        )
        return MembershipResponse(
            adult_id=invitation["accepted_by"], family_id=family_id, status="active"
        )


@router.delete("/families/{family_id}/guardians/{guardian_id}", response_model=MembershipResponse)
def revoke_guardian(
    family_id: UUID, guardian_id: UUID, request: Request, actor: Authenticated
) -> MembershipResponse:
    database: TransactionalDatabase = request.app.state.database
    now = datetime.now(UTC)
    with database.transaction() as connection:
        require_owner(connection, family_id, actor.adult_id)
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
                .where(and_(resources.c.family_id == family_id, resources.c.deleted_at.is_(None)))
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
