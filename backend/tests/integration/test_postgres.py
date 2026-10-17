import os
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import ProgrammingError

from alembic import command
from sarti_backend.db.schema import (
    adults,
    families,
    memberships,
    personal_backups,
    resources,
    sync_operations,
)

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
    assert version == "13"
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
        "personal_backups",
    }.issubset(set(inspect(engine).get_table_names()))

    # This destructive migration fixture deliberately removes test operations;
    # protocol-2 ciphertext otherwise blocks unsafe version-tag removal.
    with engine.begin() as connection:
        connection.execute(sync_operations.delete())
        connection.execute(personal_backups.delete())
        connection.execute(
            resources.delete().where(
                resources.c.kind.in_(
                    (
                        "personal_calendar",
                        "participant_profile",
                        "admin_audit",
                        "care_calendar",
                        "classroom_calendar",
                        "activity_calendar",
                        "school_calendar",
                    )
                )
            )
        )
        # Destructive roundtrip uses an empty authorization fixture: new scoped
        # roles/context kinds must otherwise block unsafe downgrade.
        connection.execute(families.delete())
    # A scoped administrator cannot become an implicit legacy owner on
    # downgrade. Exercise the actual Alembic chain; all revisions roll back.
    adult_id, family_id, resource_id = uuid4(), uuid4(), uuid4()
    now = datetime.now(UTC)
    with engine.begin() as connection:
        connection.execute(
            adults.insert().values(id=adult_id, webauthn_user_handle=os.urandom(32), created_at=now)
        )
        connection.execute(
            families.insert().values(id=family_id, created_by=adult_id, created_at=now)
        )
        connection.execute(
            memberships.insert().values(
                family_id=family_id,
                adult_id=adult_id,
                role="administrator",
                status="active",
                created_at=now,
            )
        )
        connection.execute(
            resources.insert().values(
                id=resource_id, family_id=family_id, kind="calendar", key_epoch=1, created_at=now
            )
        )
    with pytest.raises(ProgrammingError, match="downgrade would escalate access"):
        command.downgrade(config, "0011")
    with engine.begin() as connection:
        assert (
            connection.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
            == "0013"
        )
        assert (
            connection.execute(
                text("SELECT role FROM memberships WHERE adult_id=:adult"), {"adult": adult_id}
            ).scalar_one()
            == "administrator"
        )
        connection.execute(families.delete().where(families.c.id == family_id))
        connection.execute(adults.delete().where(adults.c.id == adult_id))
    command.downgrade(config, "base")
    assert "schema_metadata" not in inspect(engine).get_table_names()
    command.upgrade(config, "head")
    engine.dispose()
