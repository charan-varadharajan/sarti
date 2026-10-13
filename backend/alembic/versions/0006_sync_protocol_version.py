"""Versioned sync metadata; preserve legacy ciphertext verbatim."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "sync_operations",
        sa.Column("protocol_version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_check_constraint(
        "ck_sync_protocol_version", "sync_operations", "protocol_version IN (1, 2)"
    )
    op.execute(
        "UPDATE schema_metadata SET value = '6', updated_at = now() WHERE key = 'schema_version'"
    )


def downgrade() -> None:
    # Never silently turn v2 ciphertext into a legacy envelope.
    if (
        op.get_bind()
        .execute(sa.text("SELECT 1 FROM sync_operations WHERE protocol_version = 2 LIMIT 1"))
        .first()
    ):
        raise RuntimeError("Cannot remove protocol version while protocol-2 ciphertext remains.")
    op.drop_constraint("ck_sync_protocol_version", "sync_operations", type_="check")
    op.drop_column("sync_operations", "protocol_version")
    op.execute(
        "UPDATE schema_metadata SET value = '5', updated_at = now() WHERE key = 'schema_version'"
    )
