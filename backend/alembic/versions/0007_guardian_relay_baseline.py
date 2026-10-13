"""Starting cursor for an approved guardian's encrypted initial handoff."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "memberships",
        sa.Column("sync_start_cursor", sa.BigInteger(), nullable=False, server_default="0"),
    )
    op.create_check_constraint("ck_membership_sync_start", "memberships", "sync_start_cursor >= 0")
    op.execute("UPDATE schema_metadata SET value='7', updated_at=now() WHERE key='schema_version'")


def downgrade() -> None:
    if (
        op.get_bind()
        .execute(sa.text("SELECT 1 FROM memberships WHERE sync_start_cursor > 0 LIMIT 1"))
        .first()
    ):
        raise RuntimeError("Cannot remove an active guardian relay baseline.")
    op.drop_constraint("ck_membership_sync_start", "memberships", type_="check")
    op.drop_column("memberships", "sync_start_cursor")
    op.execute("UPDATE schema_metadata SET value='6', updated_at=now() WHERE key='schema_version'")
