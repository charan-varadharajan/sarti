"""RETENTION-MIG-002 preserves ciphertext; defaults do not delete legacy history."""

import os
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text

from alembic import command

pytestmark = pytest.mark.integration


def test_retention_migration_and_guard() -> None:
    engine = create_engine(os.environ["SARTI_DATABASE_URL"])
    config = Config("alembic.ini")
    adult, family = uuid4(), uuid4()
    now = datetime.now(UTC)
    with engine.begin() as c:
        c.execute(
            text(
                "INSERT INTO adults(id,webauthn_user_handle,created_at) VALUES (:id,:handle,:now)"
            ),
            {"id": adult, "handle": b"synthetic", "now": now},
        )
        c.execute(
            text(
                "INSERT INTO families(id,created_by,created_at,retention_revision) "
                "VALUES (:id,:adult,:now,1)"
            ),
            {"id": family, "adult": adult, "now": now},
        )
        original_revision = c.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
        before = c.execute(
            text("SELECT operation_id,ciphertext FROM sync_operations ORDER BY operation_id")
        ).all()
    try:
        with pytest.raises(RuntimeError, match="Cannot discard configured"):
            command.downgrade(config, "0008")
        with engine.begin() as c:
            assert (
                c.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
                == original_revision
            )
            c.execute(text("UPDATE families SET retention_revision=0 WHERE id=:id"), {"id": family})
        command.downgrade(config, "0008")
        command.upgrade(config, "head")
        with engine.begin() as c:
            row = c.execute(
                text(
                    "SELECT retention_period,retention_enabled,retention_revision "
                    "FROM families WHERE id=:id"
                ),
                {"id": family},
            ).one()
            assert tuple(row) == ("week", False, 0)
            assert (
                c.execute(
                    text(
                        "SELECT operation_id,ciphertext FROM sync_operations ORDER BY operation_id"
                    )
                ).all()
                == before
            )
    finally:
        with engine.begin() as c:
            c.execute(text("DELETE FROM families WHERE id=:id"), {"id": family})
            c.execute(text("DELETE FROM adults WHERE id=:id"), {"id": adult})
        engine.dispose()
