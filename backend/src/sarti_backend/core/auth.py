import hashlib
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated, Any, Protocol
from uuid import UUID

from fastapi import Header, Request
from sqlalchemy import Connection, and_, select

from sarti_backend.core.errors import AuthenticationRequired
from sarti_backend.db.schema import devices, sessions
from sarti_backend.households.expiry import expire_memberships


class ConnectableDatabase(Protocol):
    def connect(self) -> Connection: ...

    def transaction(self) -> Any: ...


@dataclass(frozen=True, slots=True)
class AuthenticatedDevice:
    adult_id: UUID
    device_id: UUID


def _token_digest(token: str) -> bytes:
    return hashlib.sha256(token.encode("ascii")).digest()


def require_device(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
) -> AuthenticatedDevice:
    if authorization is None or not authorization.startswith("Bearer "):
        raise AuthenticationRequired
    token = authorization.removeprefix("Bearer ")
    if len(token) < 32 or len(token) > 256 or not token.isascii():
        raise AuthenticationRequired
    database: ConnectableDatabase = request.app.state.database
    statement = (
        select(sessions.c.adult_id, sessions.c.device_id)
        .join(devices, devices.c.id == sessions.c.device_id)
        .where(
            and_(
                sessions.c.token_digest == _token_digest(token),
                sessions.c.expires_at > datetime.now(UTC),
                sessions.c.revoked_at.is_(None),
                devices.c.state == "active",
            )
        )
    )
    with database.connect() as connection:
        row = connection.execute(statement).one_or_none()
    if row is None:
        raise AuthenticationRequired
    with database.transaction() as connection:
        expire_memberships(connection, row.adult_id)
    return AuthenticatedDevice(adult_id=row.adult_id, device_id=row.device_id)
