"""Family-managed mobile calendar retention (ADR-039)."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "families", sa.Column("retention_period", sa.Text(), nullable=False, server_default="week")
    )
    op.add_column(
        "families",
        sa.Column("retention_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "families",
        sa.Column("retention_revision", sa.BigInteger(), nullable=False, server_default="0"),
    )
    op.create_check_constraint(
        "ck_family_retention_period",
        "families",
        "retention_period IN ('week','month','quarter','year','never')",
    )
    op.create_check_constraint(
        "ck_family_retention_revision", "families", "retention_revision >= 0"
    )
    op.execute("UPDATE schema_metadata SET value='9', updated_at=now() WHERE key='schema_version'")


def downgrade() -> None:
    if (
        op.get_bind()
        .execute(sa.text("SELECT 1 FROM families WHERE retention_revision > 0 LIMIT 1"))
        .first()
    ):
        raise RuntimeError("Cannot discard configured calendar retention policies.")
    op.drop_constraint("ck_family_retention_revision", "families", type_="check")
    op.drop_constraint("ck_family_retention_period", "families", type_="check")
    for column in ("retention_revision", "retention_enabled", "retention_period"):
        op.drop_column("families", column)
    op.execute("UPDATE schema_metadata SET value='8', updated_at=now() WHERE key='schema_version'")
