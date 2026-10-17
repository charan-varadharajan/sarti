"""Scoped administration. Bodies carry authorization metadata and ciphertext only."""

import hashlib
import json
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import delete, func, select, update

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import (
    ConflictDetected,
    InvalidRequest,
    PermissionDenied,
    TenantAccessDenied,
)
from sarti_backend.db.schema import (
    adults,
    context_audit,
    devices,
    families,
    memberships,
    permissions,
    resources,
)
from sarti_backend.households.authorization import (
    require_active_member,
    require_owner,
    require_resource_permission,
)
from sarti_backend.households.roles import ADMIN_ROLES, ContextKind, Role, role_allowed
from sarti_backend.identity.step_up import consume_step_up, current_session
from sarti_backend.sync.envelope import OperationUpload, _decode, _encode

Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]
router = APIRouter(prefix="/v1/contexts", tags=["scoped administration"])


class ContextResource(BaseModel):
    id: UUID
    kind: str
    key_epoch: int = Field(gt=0)
    permission: Literal["read", "write", "admin"]


class ContextResponse(BaseModel):
    id: UUID
    kind: ContextKind
    role: Role | Literal["owner"]
    acl_revision: int = Field(ge=0)
    resources: list[ContextResource]


class ContextSummary(BaseModel):
    id: UUID
    context_kind: ContextKind
    acl_revision: int = Field(ge=0)
    role: Role | Literal["owner"]
    status: Literal["pending", "active"]
    expires_at: datetime | None


class PublicDevice(BaseModel):
    device_id: UUID
    encryption_public_key: str
    signing_public_key: str
    key_digest: str


class MemberResponse(BaseModel):
    adult_id: UUID
    role: Role | Literal["owner"]
    status: Literal["pending", "active", "revoked"]
    expires_at: datetime | None
    device: PublicDevice | None
    permissions: list["Grant"]


class ChangeOutcome(BaseModel):
    adult_id: UUID
    context_id: UUID
    role: Role
    status: Literal["active", "revoked"]
    acl_revision: int = Field(ge=0)


class AuditResponse(BaseModel):
    id: UUID
    family_id: UUID
    actor_device_id: UUID
    action: Literal["admin.change", "permissions.change", "membership.revoke"]
    target_id: UUID
    acl_revision: int = Field(gt=0)
    envelope: OperationUpload
    outcome: ChangeOutcome
    created_at: datetime
    expires_at: datetime


class ContextCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: ContextKind


class Grant(BaseModel):
    model_config = ConfigDict(extra="forbid")
    resource_id: UUID
    permission: str = Field(pattern="^(read|write|admin)$")


class MemberChange(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Role
    expected_device_id: UUID | None = None
    expected_key_digest: str | None = Field(default=None, pattern="^[a-f0-9]{64}$")
    revoked: bool = False
    expires_at: datetime | None = None
    permissions: list[Grant] = Field(max_length=100)
    expected_revision: int = Field(ge=0)
    proof: str = Field(min_length=32, max_length=256)
    audit: OperationUpload

    @model_validator(mode="after")
    def bounds(self) -> "MemberChange":
        if self.expires_at is not None and (
            self.expires_at.tzinfo is None or self.expires_at <= datetime.now(UTC)
        ):
            raise ValueError("expiry must be a future instant")
        if len({p.resource_id for p in self.permissions}) != len(self.permissions):
            raise ValueError("duplicate permission")
        if len(self.audit.ciphertext) > 87384:
            raise ValueError("audit too large")
        return self


@router.post("", status_code=201, response_model=ContextResponse)
def create_context(
    payload: ContextCreate, request: Request, actor: Authenticated
) -> dict[str, Any]:
    context_id = uuid4()
    now = datetime.now(UTC)
    admin = {
        ContextKind.HOUSEHOLD: Role.ADMINISTRATOR,
        ContextKind.ACTIVITY: Role.ADMINISTRATOR,
        ContextKind.CLASSROOM: Role.CLASSROOM_ADMIN,
        ContextKind.SCHOOL: Role.SCHOOL_ADMIN,
    }[payload.kind]
    calendar_kind = {
        ContextKind.HOUSEHOLD: "calendar",
        ContextKind.ACTIVITY: "activity_calendar",
        ContextKind.CLASSROOM: "classroom_calendar",
        ContextKind.SCHOOL: "school_calendar",
    }[payload.kind]
    resource_rows = [
        {"id": uuid4(), "family_id": context_id, "kind": kind, "key_epoch": 1, "created_at": now}
        for kind in ("family_profile", calendar_kind, "admin_audit")
    ]
    with request.app.state.database.transaction() as c:
        c.execute(select(adults.c.id).where(adults.c.id == actor.adult_id).with_for_update())
        current_session(c, request, actor)
        c.execute(
            families.insert().values(
                id=context_id,
                created_by=actor.adult_id,
                created_at=now,
                context_kind=payload.kind,
                retention_enabled=payload.kind == ContextKind.HOUSEHOLD,
            )
        )
        c.execute(
            memberships.insert().values(
                family_id=context_id,
                adult_id=actor.adult_id,
                role=admin,
                status="active",
                created_at=now,
            )
        )
        c.execute(resources.insert(), resource_rows)
        c.execute(
            permissions.insert(),
            [
                {"resource_id": r["id"], "adult_id": actor.adult_id, "permission": "admin"}
                for r in resource_rows
            ],
        )
    return {
        "id": str(context_id),
        "kind": payload.kind,
        "role": admin,
        "acl_revision": 0,
        "resources": [
            {"id": str(r["id"]), "kind": r["kind"], "key_epoch": 1, "permission": "admin"}
            for r in resource_rows
        ],
    }


@router.get("", response_model=list[ContextSummary])
def list_contexts(request: Request, actor: Authenticated) -> list[dict[str, Any]]:
    with request.app.state.database.connect() as c:
        rows = (
            c.execute(
                select(
                    families.c.id,
                    families.c.context_kind,
                    families.c.acl_revision,
                    memberships.c.role,
                    memberships.c.status,
                    memberships.c.expires_at,
                )
                .join(memberships, memberships.c.family_id == families.c.id)
                .where(
                    memberships.c.adult_id == actor.adult_id,
                    memberships.c.status != "revoked",
                    families.c.deleted_at.is_(None),
                )
            )
            .mappings()
            .all()
        )
        return [dict(row) for row in rows]


@router.get("/{context_id}", response_model=ContextResponse)
def get_context(context_id: UUID, request: Request, actor: Authenticated) -> dict[str, Any]:
    with request.app.state.database.connect() as c:
        role = require_active_member(c, context_id, actor.adult_id)
        context = c.execute(select(families).where(families.c.id == context_id)).mappings().one()
        visible = []
        for row in c.execute(
            select(resources).where(
                resources.c.family_id == context_id, resources.c.deleted_at.is_(None)
            )
        ).mappings():
            try:
                require_resource_permission(
                    c,
                    family_id=context_id,
                    resource_id=row["id"],
                    adult_id=actor.adult_id,
                    required="read",
                )
            except (PermissionDenied, TenantAccessDenied):
                continue
            grant = c.execute(
                select(permissions.c.permission).where(
                    permissions.c.resource_id == row["id"], permissions.c.adult_id == actor.adult_id
                )
            ).scalar_one_or_none()
            visible.append(
                {
                    "id": row["id"],
                    "kind": row["kind"],
                    "key_epoch": row["key_epoch"],
                    "permission": "admin"
                    if row["private_adult_id"] == actor.adult_id or role == "owner"
                    else grant,
                }
            )
        return {
            "id": context_id,
            "kind": context["context_kind"],
            "role": role,
            "acl_revision": context["acl_revision"],
            "resources": visible,
        }


@router.get("/{context_id}/members", response_model=list[MemberResponse])
def list_members(context_id: UUID, request: Request, actor: Authenticated) -> list[dict[str, Any]]:
    with request.app.state.database.connect() as c:
        require_owner(c, context_id, actor.adult_id)
        rows = (
            c.execute(
                select(
                    memberships.c.adult_id,
                    memberships.c.role,
                    memberships.c.status,
                    memberships.c.expires_at,
                ).where(memberships.c.family_id == context_id)
            )
            .mappings()
            .all()
        )
        result = []
        for row in rows:
            member = dict(row)
            device = (
                c.execute(
                    select(devices).where(
                        devices.c.adult_id == row["adult_id"], devices.c.state == "active"
                    )
                )
                .mappings()
                .one_or_none()
            )
            member["device"] = (
                None
                if device is None or row["status"] == "revoked"
                else {
                    "device_id": device["id"],
                    "encryption_public_key": _encode(device["encryption_public_key"]),
                    "signing_public_key": _encode(device["signing_public_key"]),
                    "key_digest": hashlib.sha256(
                        device["signing_public_key"] + device["encryption_public_key"]
                    ).hexdigest(),
                }
            )
            member["permissions"] = [
                dict(grant)
                for grant in c.execute(
                    select(permissions.c.resource_id, permissions.c.permission)
                    .join(resources, resources.c.id == permissions.c.resource_id)
                    .where(
                        resources.c.family_id == context_id,
                        resources.c.private_adult_id.is_(None),
                        permissions.c.adult_id == row["adult_id"],
                    )
                ).mappings()
            ]
            result.append(member)
        return result


def action_for(current: str, payload: MemberChange) -> str:
    if payload.revoked:
        return "membership.revoke"
    if current != payload.role:
        return "admin.change"
    return "permissions.change"


@router.put("/{context_id}/members/{adult_id}", response_model=ChangeOutcome)
def change_member(
    context_id: UUID, adult_id: UUID, payload: MemberChange, request: Request, actor: Authenticated
) -> dict[str, Any]:
    now = datetime.now(UTC)
    with request.app.state.database.transaction() as c:
        context = (
            c.execute(select(families).where(families.c.id == context_id).with_for_update())
            .mappings()
            .one_or_none()
        )
        require_owner(c, context_id, actor.adult_id)
        c.execute(
            select(adults.c.id)
            .where(adults.c.id.in_((actor.adult_id, adult_id)))
            .order_by(adults.c.id)
            .with_for_update()
        ).all()
        # Serialize epoch validation and grant changes with device replacement,
        # relay publication and sealed-key grants, in stable resource order.
        c.execute(
            select(resources.c.id)
            .where(
                resources.c.family_id == context_id,
                resources.c.private_adult_id.is_(None),
            )
            .order_by(resources.c.id)
            .with_for_update()
        ).all()
        target = (
            c.execute(
                select(memberships)
                .where(memberships.c.family_id == context_id, memberships.c.adult_id == adult_id)
                .with_for_update()
            )
            .mappings()
            .one_or_none()
        )
        if context is None or target is None:
            raise TenantAccessDenied
        if not role_allowed(context["context_kind"], payload.role):
            raise PermissionDenied
        action = action_for(target["role"], payload)
        document = payload.model_dump(mode="json", exclude={"proof"})
        document["permissions"] = sorted(document["permissions"], key=lambda p: p["resource_id"])
        digest = hashlib.sha256(
            json.dumps(document, sort_keys=True, separators=(",", ":")).encode()
        ).digest()
        prior = (
            c.execute(select(context_audit).where(context_audit.c.id == payload.audit.operation_id))
            .mappings()
            .one_or_none()
        )
        if prior is not None:
            if (
                prior["family_id"] != context_id
                or prior["actor_device_id"] != actor.device_id
                or prior["target_id"] != adult_id
                or prior["request_digest"] != digest
            ):
                raise ConflictDetected()
            return dict(prior["outcome"])
        if target["status"] != "active":
            raise TenantAccessDenied
        if not payload.revoked:
            recipient = (
                c.execute(
                    select(devices).where(
                        devices.c.adult_id == adult_id, devices.c.state == "active"
                    )
                )
                .mappings()
                .one_or_none()
            )
            if (
                recipient is None
                or payload.expected_device_id != recipient["id"]
                or payload.expected_key_digest
                != hashlib.sha256(
                    recipient["signing_public_key"] + recipient["encryption_public_key"]
                ).hexdigest()
            ):
                raise ConflictDetected(
                    "The recipient device changed. Review its verification code again."
                )
        if context["acl_revision"] != payload.expected_revision:
            raise ConflictDetected("Access changed. Review it again.")
        if target["role"] in ({"owner"} | set(ADMIN_ROLES)) and (
            payload.revoked or payload.role not in ADMIN_ROLES or payload.expires_at is not None
        ):
            remaining = c.execute(
                select(func.count())
                .select_from(memberships)
                .where(
                    memberships.c.family_id == context_id,
                    memberships.c.adult_id != adult_id,
                    memberships.c.status == "active",
                    memberships.c.role.in_(["owner", *ADMIN_ROLES]),
                    memberships.c.expires_at.is_(None),
                )
            ).scalar_one()
            if remaining == 0:
                raise ConflictDetected(
                    "Keep an active administrator or explicitly close the household."
                )
        requested = {g.resource_id: g.permission for g in payload.permissions}
        if payload.revoked and requested:
            raise InvalidRequest()
        for resource_id, permission in requested.items():
            _, kind = require_resource_permission(
                c,
                family_id=context_id,
                resource_id=resource_id,
                adult_id=actor.adult_id,
                required="admin",
            )
            if kind == "personal_calendar":
                raise PermissionDenied
            if payload.role == Role.CAREGIVER and (
                kind not in {"care_calendar", "child_profile"} or permission != "read"
            ):
                raise PermissionDenied
            if payload.role in {Role.SUBSCRIBER, Role.VOLUNTEER} and permission != "read":
                raise PermissionDenied
            if payload.role not in ADMIN_ROLES and kind == "admin_audit":
                raise PermissionDenied
        audit = payload.audit
        epoch, kind = require_resource_permission(
            c,
            family_id=context_id,
            resource_id=audit.resource_id,
            adult_id=actor.adult_id,
            required="write",
        )
        if (
            kind != "admin_audit"
            or audit.family_id != context_id
            or audit.key_epoch != epoch
            or audit.protocol_version != 2
            or audit.logical_version.get(str(actor.device_id), 0) < 1
        ):
            raise PermissionDenied
        nonce = _decode(audit.nonce, 24)
        ciphertext = _decode(audit.ciphertext)
        content_digest = _decode(audit.content_digest, 32)
        if (
            hashlib.sha256(nonce + ciphertext).digest() != content_digest
            or not 17 <= len(ciphertext) <= 65536
        ):
            raise InvalidRequest()
        consume_step_up(
            c,
            request=request,
            actor=actor,
            proof=payload.proof,
            action=action,
            family_id=context_id,
            target_id=adult_id,
            revision=payload.expected_revision,
        )
        public_ids = select(resources.c.id).where(
            resources.c.family_id == context_id, resources.c.private_adult_id.is_(None)
        )
        old = dict(
            c.execute(
                select(permissions.c.resource_id, permissions.c.permission).where(
                    permissions.c.adult_id == adult_id, permissions.c.resource_id.in_(public_ids)
                )
            ).all()
        )
        lost = set(old) - set(requested)
        if lost:
            c.execute(
                update(resources)
                .where(resources.c.id.in_(lost), resources.c.deleted_at.is_(None))
                .values(key_epoch=resources.c.key_epoch + 1)
            )
        c.execute(
            delete(permissions).where(
                permissions.c.adult_id == adult_id, permissions.c.resource_id.in_(public_ids)
            )
        )
        if requested:
            c.execute(
                permissions.insert(),
                [
                    {"adult_id": adult_id, "resource_id": rid, "permission": p}
                    for rid, p in requested.items()
                ],
            )
        c.execute(
            update(memberships)
            .where(memberships.c.family_id == context_id, memberships.c.adult_id == adult_id)
            .values(
                role=payload.role,
                status="revoked" if payload.revoked else "active",
                expires_at=payload.expires_at,
                revoked_at=now if payload.revoked else None,
            )
        )
        revision = context["acl_revision"] + 1
        c.execute(update(families).where(families.c.id == context_id).values(acl_revision=revision))
        outcome = {
            "adult_id": str(adult_id),
            "context_id": str(context_id),
            "role": payload.role,
            "status": "revoked" if payload.revoked else "active",
            "acl_revision": revision,
        }
        c.execute(
            context_audit.insert().values(
                id=audit.operation_id,
                family_id=context_id,
                resource_id=audit.resource_id,
                actor_device_id=actor.device_id,
                action=action,
                target_id=adult_id,
                acl_revision=revision,
                envelope=audit.model_dump(mode="json"),
                request_digest=digest,
                outcome=outcome,
                created_at=now,
                expires_at=now + timedelta(days=30),
            )
        )
        return outcome


@router.get("/{context_id}/audit", response_model=list[AuditResponse])
def list_audit(context_id: UUID, request: Request, actor: Authenticated) -> list[dict[str, Any]]:
    with request.app.state.database.connect() as c:
        require_owner(c, context_id, actor.adult_id)
        rows = (
            c.execute(
                select(context_audit)
                .where(
                    context_audit.c.family_id == context_id,
                    context_audit.c.expires_at > datetime.now(UTC),
                )
                .order_by(context_audit.c.created_at.desc())
                .limit(100)
            )
            .mappings()
            .all()
        )
        result = []
        for row in rows:
            try:
                require_resource_permission(
                    c,
                    family_id=context_id,
                    resource_id=row["resource_id"],
                    adult_id=actor.adult_id,
                    required="read",
                )
            except PermissionDenied:
                continue
            result.append(
                {
                    k: row[k]
                    for k in (
                        "id",
                        "family_id",
                        "actor_device_id",
                        "action",
                        "target_id",
                        "acl_revision",
                        "envelope",
                        "outcome",
                        "created_at",
                        "expires_at",
                    )
                }
            )
        return result
