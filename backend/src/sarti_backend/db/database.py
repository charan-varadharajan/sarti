import logging
from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import Connection, Engine, create_engine, text

logger = logging.getLogger("sarti.database")


class Database:
    def __init__(self, database_url: str) -> None:
        self._engine: Engine = create_engine(
            database_url,
            pool_pre_ping=True,
            pool_recycle=300,
        )

    def is_ready(self) -> bool:
        try:
            with self._engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            return True
        except Exception as error:
            logger.warning(
                "database_unavailable",
                extra={"event": "database_unavailable", "error_type": type(error).__name__},
            )
            return False

    def close(self) -> None:
        self._engine.dispose()

    def connect(self) -> Connection:
        return self._engine.connect()

    @contextmanager
    def transaction(self) -> Iterator[Connection]:
        with self._engine.begin() as connection:
            yield connection
