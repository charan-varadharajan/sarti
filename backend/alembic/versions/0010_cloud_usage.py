"""Bounded optional cloud attempts, no prompt persistence (ADR-037)."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ai_usage",
        sa.Column("scope", sa.Text(), primary_key=True),
        sa.Column("bucket", sa.Date(), primary_key=True),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("attempts >= 0", name="ck_ai_usage_attempts"),
    )
    op.create_index("ix_ai_usage_expiry", "ai_usage", ["expires_at"])
    op.execute(
        "CREATE FUNCTION purge_adult_ai_usage() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN DELETE FROM ai_usage WHERE scope=OLD.id::text; RETURN OLD; END $$"
    )
    op.execute(
        "CREATE TRIGGER adult_ai_usage_delete AFTER DELETE ON adults FOR EACH ROW EXECUTE FUNCTION purge_adult_ai_usage()"
    )
    op.execute("UPDATE schema_metadata SET value='10',updated_at=now() WHERE key='schema_version'")


def downgrade() -> None:
    op.execute("DROP TRIGGER adult_ai_usage_delete ON adults")
    op.execute("DROP FUNCTION purge_adult_ai_usage()")
    op.drop_table("ai_usage")
    op.execute("UPDATE schema_metadata SET value='9',updated_at=now() WHERE key='schema_version'")
