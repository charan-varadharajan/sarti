"""Resource metadata transition for ADR-020; never handles plaintext keys."""

from uuid import UUID

from sqlalchemy import Connection, and_, or_, select, update

from sarti_backend.db.schema import families, memberships, permissions, resources


def advance_replacement_epochs(connection: Connection, adult_id: UUID) -> None:
    """Lock affected resources in stable order before revoking the old device.

    Owners can hold all family keys; guardians can hold explicitly permitted
    resource keys. Pending/revoked memberships and deleted families/resources
    do not participate. Uploads/grants take the same resource lock.
    """
    permitted = select(permissions.c.resource_id).where(permissions.c.adult_id == adult_id)
    affected_families = select(memberships.c.family_id).where(
        and_(memberships.c.adult_id == adult_id, memberships.c.status == "active")
    )
    owned_families = select(memberships.c.family_id).where(
        and_(
            memberships.c.adult_id == adult_id,
            memberships.c.status == "active",
            memberships.c.role == "owner",
        )
    )
    ids = (
        connection.execute(
            select(resources.c.id)
            .where(
                and_(
                    resources.c.family_id.in_(affected_families),
                    resources.c.family_id.in_(
                        select(families.c.id).where(families.c.deleted_at.is_(None))
                    ),
                    resources.c.deleted_at.is_(None),
                    or_(resources.c.family_id.in_(owned_families), resources.c.id.in_(permitted)),
                )
            )
            .order_by(resources.c.id)
            .with_for_update()
        )
        .scalars()
        .all()
    )
    if ids:
        connection.execute(
            update(resources)
            .where(resources.c.id.in_(ids))
            .values(key_epoch=resources.c.key_epoch + 1)
        )
