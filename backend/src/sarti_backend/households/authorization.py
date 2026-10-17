from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import Connection, and_, or_, select

from sarti_backend.core.errors import PermissionDenied, TenantAccessDenied
from sarti_backend.db.schema import families, memberships, permissions, resources
from sarti_backend.households.roles import permits, role_allowed

_PERMISSION_LEVEL = {"read": 1, "write": 2, "admin": 3}


def require_active_member(connection: Connection, family_id: UUID, adult_id: UUID) -> str:
    row = connection.execute(
        select(memberships.c.role, families.c.context_kind)
        .join(families, families.c.id == memberships.c.family_id)
        .where(
            and_(
                memberships.c.family_id == family_id,
                memberships.c.adult_id == adult_id,
                memberships.c.status == "active",
                families.c.deleted_at.is_(None),
                or_(
                    memberships.c.expires_at.is_(None), memberships.c.expires_at > datetime.now(UTC)
                ),
            )
        )
    ).one_or_none()
    if row is None:
        raise TenantAccessDenied
    if not role_allowed(
        str(row.context_kind), "administrator" if row.role == "owner" else str(row.role)
    ):
        raise PermissionDenied
    return str(row.role)


def require_owner(connection: Connection, family_id: UUID, adult_id: UUID) -> None:
    if require_active_member(connection, family_id, adult_id) not in {
        "owner",
        "administrator",
        "classroom_administrator",
        "school_administrator",
    }:
        raise PermissionDenied


def require_resource_permission(
    connection: Connection,
    *,
    family_id: UUID,
    resource_id: UUID,
    adult_id: UUID,
    required: str,
) -> tuple[int, str]:
    role = require_active_member(connection, family_id, adult_id)
    resource = connection.execute(
        select(resources.c.key_epoch, resources.c.kind, resources.c.private_adult_id).where(
            and_(
                resources.c.id == resource_id,
                resources.c.family_id == family_id,
                resources.c.deleted_at.is_(None),
            )
        )
    ).one_or_none()
    if resource is None:
        raise TenantAccessDenied
    if resource.kind == "personal_calendar":
        if resource.private_adult_id != adult_id:
            raise PermissionDenied
    elif role != "owner":
        permission = connection.execute(
            select(permissions.c.permission).where(
                and_(
                    permissions.c.resource_id == resource_id,
                    permissions.c.adult_id == adult_id,
                )
            )
        ).scalar_one_or_none()
        kind = connection.execute(
            select(families.c.context_kind).where(families.c.id == family_id)
        ).scalar_one()
        action = {"read": "content.read", "write": "content.write", "admin": "keys.grant"}.get(
            required, "unknown"
        )
        if (
            permission is None
            or _PERMISSION_LEVEL[str(permission)] < _PERMISSION_LEVEL[required]
            or not permits(str(kind), role, action, str(permission))
        ):
            raise PermissionDenied
    return int(resource.key_epoch), str(resource.kind)
