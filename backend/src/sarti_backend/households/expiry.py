"""Immediate contextual expiry/rotation on authenticated requests, plus maintenance."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import Connection, delete, select, update

from sarti_backend.db.schema import context_audit, families, memberships, permissions, resources


def expire_memberships(connection: Connection, adult_id: UUID | None = None) -> int:
    now = datetime.now(UTC)
    context_ids = (
        select(memberships.c.family_id).where(
            memberships.c.adult_id == adult_id, memberships.c.status == "active"
        )
        if adult_id
        else select(families.c.id)
    )
    contexts = (
        connection.execute(
            select(families.c.id)
            .where(families.c.id.in_(context_ids), families.c.deleted_at.is_(None))
            .order_by(families.c.id)
            .with_for_update()
        )
        .scalars()
        .all()
    )
    count = 0
    for context_id in contexts:
        expired = (
            connection.execute(
                select(memberships.c.adult_id)
                .where(
                    memberships.c.family_id == context_id,
                    memberships.c.status == "active",
                    memberships.c.expires_at <= now,
                )
                .with_for_update()
            )
            .scalars()
            .all()
        )
        if not expired:
            continue
        ids = (
            connection.execute(
                select(resources.c.id)
                .join(permissions, permissions.c.resource_id == resources.c.id)
                .where(
                    resources.c.family_id == context_id,
                    resources.c.private_adult_id.is_(None),
                    resources.c.deleted_at.is_(None),
                    permissions.c.adult_id.in_(expired),
                )
                .order_by(resources.c.id)
                .with_for_update(of=resources)
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
        connection.execute(
            delete(permissions).where(
                permissions.c.adult_id.in_(expired),
                permissions.c.resource_id.in_(
                    select(resources.c.id).where(resources.c.family_id == context_id)
                ),
            )
        )
        connection.execute(
            update(memberships)
            .where(memberships.c.family_id == context_id, memberships.c.adult_id.in_(expired))
            .values(status="revoked", revoked_at=now)
        )
        connection.execute(
            update(families)
            .where(families.c.id == context_id)
            .values(acl_revision=families.c.acl_revision + 1)
        )
        count += len(expired)
    connection.execute(delete(context_audit).where(context_audit.c.expires_at <= now))
    return count
