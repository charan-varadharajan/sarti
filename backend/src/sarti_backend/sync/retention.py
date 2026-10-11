from datetime import UTC, datetime

from sqlalchemy import Connection, delete

from sarti_backend.db.schema import sync_operations


def delete_expired_operations(connection: Connection, now: datetime | None = None) -> int:
    result = connection.execute(
        delete(sync_operations).where(sync_operations.c.expires_at <= (now or datetime.now(UTC)))
    )
    return int(result.rowcount or 0)
