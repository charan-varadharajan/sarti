from uuid import UUID

from sqlalchemy import Connection, and_, select

from sarti_backend.core.errors import PermissionDenied, TenantAccessDenied
from sarti_backend.db.schema import memberships, permissions, resources

_PERMISSION_LEVEL = {"read": 1, "write": 2, "admin": 3}


def require_active_member(connection: Connection, family_id: UUID, adult_id: UUID) -> str:
    row = connection.execute(
        select(memberships.c.role).where(
            and_(
                memberships.c.family_id == family_id,
                memberships.c.adult_id == adult_id,
                memberships.c.status == "active",
            )
        )
    ).one_or_none()
    if row is None:
        raise TenantAccessDenied
    return str(row.role)


def require_owner(connection: Connection, family_id: UUID, adult_id: UUID) -> None:
    if require_active_member(connection, family_id, adult_id) != "owner":
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
        if permission is None or _PERMISSION_LEVEL[str(permission)] < _PERMISSION_LEVEL[required]:
            raise PermissionDenied
    return int(resource.key_epoch), str(resource.kind)
