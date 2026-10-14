from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Request, Response
from sqlalchemy import Connection, Table, and_, delete, select
from sqlalchemy.sql.elements import ColumnElement

from sarti_backend.api.sync import TransactionalDatabase
from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import ConflictDetected, InvalidRequest, TenantAccessDenied
from sarti_backend.db.schema import families, family_backups, personal_backups
from sarti_backend.households.authorization import require_active_member, require_owner

router = APIRouter(prefix="/v1/families/{family_id}", tags=["encrypted-backup"])
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]
MAX_BACKUP_BYTES = 10 * 1024 * 1024


def _store(
    request: Request, family_id: UUID, actor: AuthenticatedDevice
) -> tuple[Table, ColumnElement[bool]]:
    if request.url.path.endswith("/personal-backup"):
        return personal_backups, and_(
            personal_backups.c.family_id == family_id, personal_backups.c.adult_id == actor.adult_id
        )
    return family_backups, family_backups.c.family_id == family_id


def _authorize(
    connection: Connection, family_id: UUID, actor: AuthenticatedDevice, personal: bool
) -> None:
    if personal:
        require_active_member(connection, family_id, actor.adult_id)
    else:
        require_owner(connection, family_id, actor.adult_id)


def authorize(
    database: TransactionalDatabase,
    family_id: UUID,
    actor: AuthenticatedDevice,
    personal: bool = False,
) -> None:
    with database.connect() as connection:
        _authorize(connection, family_id, actor, personal)
        exists = connection.execute(
            select(families.c.id).where(families.c.id == family_id, families.c.deleted_at.is_(None))
        ).scalar_one_or_none()
        if exists is None:
            raise TenantAccessDenied


@router.put(
    "/personal-backup",
    status_code=204,
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {
                "application/octet-stream": {
                    "schema": {"type": "string", "format": "binary", "maxLength": MAX_BACKUP_BYTES}
                }
            },
        }
    },
)
@router.put(
    "/backup",
    status_code=204,
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {
                "application/octet-stream": {
                    "schema": {"type": "string", "format": "binary", "maxLength": MAX_BACKUP_BYTES}
                }
            },
        }
    },
)
async def upload_backup(
    family_id: UUID,
    request: Request,
    actor: Authenticated,
    expected_revision: Annotated[int, Header(ge=0, alias="X-Backup-Revision")],
) -> Response:
    database: TransactionalDatabase = request.app.state.database
    table, scope = _store(request, family_id, actor)
    personal = table is personal_backups
    authorize(database, family_id, actor, personal)
    # Bound the stream before accumulating it; never log request bodies.
    blob = bytearray()
    async for chunk in request.stream():
        if len(blob) + len(chunk) > MAX_BACKUP_BYTES:
            raise InvalidRequest("Backup exceeds the size limit.")
        blob.extend(chunk)
    if len(blob) < 94 or blob[:5] != b"SART\x02":
        raise InvalidRequest("Only encrypted backup format v2 is accepted.")
    with database.transaction() as connection:
        # Serialize revision updates, including the first upload.
        family = connection.execute(
            select(families.c.id)
            .where(families.c.id == family_id, families.c.deleted_at.is_(None))
            .with_for_update()
        ).scalar_one_or_none()
        if family is None:
            raise TenantAccessDenied
        _authorize(connection, family_id, actor, personal)
        current = connection.execute(select(table.c.revision).where(scope)).scalar_one_or_none()
        if (current or 0) != expected_revision:
            raise ConflictDetected("A newer backup exists. Refresh before replacing it.")
        values = {
            "revision": expected_revision + 1,
            "ciphertext": bytes(blob),
            "updated_at": datetime.now(UTC),
        }
        if current is None:
            connection.execute(
                table.insert().values(
                    family_id=family_id,
                    **({"adult_id": actor.adult_id} if personal else {}),
                    **values,
                )
            )
        else:
            connection.execute(table.update().where(scope).values(**values))
    return Response(status_code=204, headers={"X-Backup-Revision": str(expected_revision + 1)})


@router.get(
    "/personal-backup",
    response_class=Response,
    responses={
        200: {
            "content": {
                "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
            }
        }
    },
)
@router.get(
    "/backup",
    response_class=Response,
    responses={
        200: {
            "content": {
                "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
            }
        }
    },
)
def download_backup(family_id: UUID, request: Request, actor: Authenticated) -> Response:
    database: TransactionalDatabase = request.app.state.database
    table, scope = _store(request, family_id, actor)
    personal = table is personal_backups
    authorize(database, family_id, actor, personal)
    with database.connect() as connection:
        row = connection.execute(select(table).where(scope)).mappings().one_or_none()
    if row is None:
        raise TenantAccessDenied
    return Response(
        content=row["ciphertext"],
        media_type="application/octet-stream",
        headers={
            "X-Backup-Revision": str(row["revision"]),
            "X-Backup-Updated-At": row["updated_at"].isoformat(),
            "Cache-Control": "no-store",
        },
    )


@router.delete("/personal-backup", status_code=204)
@router.delete("/backup", status_code=204)
def delete_backup(family_id: UUID, request: Request, actor: Authenticated) -> Response:
    database: TransactionalDatabase = request.app.state.database
    table, scope = _store(request, family_id, actor)
    with database.transaction() as connection:
        _authorize(connection, family_id, actor, table is personal_backups)
        connection.execute(delete(table).where(scope))
    return Response(status_code=204)
