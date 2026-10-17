"""Current-session, operation-bound WebAuthn proof. Never replaces a device."""

import hashlib
from datetime import UTC, datetime
from uuid import UUID

from fastapi import Request
from sqlalchemy import Connection, and_, select, update

from sarti_backend.core.auth import AuthenticatedDevice
from sarti_backend.core.errors import AuthenticationRequired, ConflictDetected, PermissionDenied
from sarti_backend.db.schema import devices, families, sensitive_authorizations, sessions
from sarti_backend.households.authorization import require_active_member


def current_session(connection: Connection, request: Request, actor: AuthenticatedDevice) -> UUID:
    authorization = request.headers.get("Authorization", "")
    token = authorization.removeprefix("Bearer ")
    if (
        not authorization.startswith("Bearer ")
        or not token.isascii()
        or not 32 <= len(token) <= 256
    ):
        raise AuthenticationRequired
    row = connection.execute(
        select(sessions.c.id)
        .join(devices, devices.c.id == sessions.c.device_id)
        .where(
            and_(
                sessions.c.token_digest == hashlib.sha256(token.encode("ascii")).digest(),
                sessions.c.adult_id == actor.adult_id,
                sessions.c.device_id == actor.device_id,
                sessions.c.revoked_at.is_(None),
                sessions.c.expires_at > datetime.now(UTC),
                devices.c.state == "active",
            )
        )
        .with_for_update(of=(sessions, devices))
    ).scalar_one_or_none()
    if row is None:
        raise AuthenticationRequired
    return UUID(str(row))


def check_scope(
    connection: Connection,
    actor: AuthenticatedDevice,
    family_id: UUID | None,
    target_id: UUID,
    revision: int,
) -> None:
    if family_id is None:
        if target_id != actor.adult_id or revision != 0:
            raise PermissionDenied
        return
    require_active_member(connection, family_id, actor.adult_id)
    current = connection.execute(
        select(families.c.acl_revision).where(
            and_(families.c.id == family_id, families.c.deleted_at.is_(None))
        )
    ).scalar_one_or_none()
    if current is None or current != revision:
        raise ConflictDetected("Access changed. Review the action again.")


def consume_step_up(
    connection: Connection,
    *,
    request: Request,
    actor: AuthenticatedDevice,
    proof: str,
    action: str,
    family_id: UUID | None,
    target_id: UUID,
    revision: int,
) -> None:
    """Consume only in the same transaction as the authorized sensitive mutation.

    Caller must additionally authorize the action/resource under its locks; this
    proof demonstrates fresh identity, never grants a role or content permission.
    """
    if not proof.isascii() or not 32 <= len(proof) <= 256:
        raise AuthenticationRequired
    session_id = current_session(connection, request, actor)
    check_scope(connection, actor, family_id, target_id, revision)
    row = (
        connection.execute(
            select(sensitive_authorizations)
            .where(
                sensitive_authorizations.c.proof_digest
                == hashlib.sha256(proof.encode("ascii")).digest()
            )
            .with_for_update()
        )
        .mappings()
        .one_or_none()
    )
    if (
        row is None
        or row["session_id"] != session_id
        or row["action"] != action
        or row["family_id"] != family_id
        or row["target_id"] != target_id
        or row["acl_revision"] != revision
        or row["verified_at"] is None
        or row["consumed_at"] is not None
        or row["expires_at"] <= datetime.now(UTC)
    ):
        raise AuthenticationRequired
    connection.execute(
        update(sensitive_authorizations)
        .where(sensitive_authorizations.c.id == row["id"])
        .values(consumed_at=datetime.now(UTC))
    )
