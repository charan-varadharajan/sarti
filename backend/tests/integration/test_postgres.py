import os

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text

from alembic import command
from sarti_backend.db.schema import sync_operations

pytestmark = pytest.mark.integration


def test_migrations_and_database_readiness() -> None:
    database_url = os.environ["SARTI_DATABASE_URL"]
    config = Config("alembic.ini")
    command.upgrade(config, "head")

    engine = create_engine(database_url)
    with engine.connect() as connection:
        version = connection.execute(
            text("SELECT value FROM schema_metadata WHERE key = 'schema_version'")
        ).scalar_one()
    assert version == "6"
    assert "schema_metadata" in inspect(engine).get_table_names()

    assert {
        "adults",
        "devices",
        "families",
        "memberships",
        "resources",
        "sync_operations",
        "email_suggestions",
        "email_suggestion_deliveries",
        "family_backups",
    }.issubset(set(inspect(engine).get_table_names()))

    # This destructive migration fixture deliberately removes test operations;
    # protocol-2 ciphertext otherwise blocks unsafe version-tag removal.
    with engine.begin() as connection:
        connection.execute(sync_operations.delete())
    command.downgrade(config, "base")
    assert "schema_metadata" not in inspect(engine).get_table_names()
    command.upgrade(config, "head")
    engine.dispose()
