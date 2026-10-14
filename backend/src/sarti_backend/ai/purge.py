"""Run daily before enabling cloud assist: python -m sarti_backend.ai.purge."""

from datetime import UTC, datetime

from sqlalchemy import delete

from sarti_backend.core.config import get_settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import ai_usage


def main() -> None:
    database = Database(get_settings().database_url)
    try:
        with database.transaction() as connection:
            connection.execute(delete(ai_usage).where(ai_usage.c.expires_at <= datetime.now(UTC)))
    finally:
        database.close()


if __name__ == "__main__":
    main()
