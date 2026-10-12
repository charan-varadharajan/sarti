"""Replace plaintext email suggestions with per-device sealed ciphertext.

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-11
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Existing Stage 3 suggestions were persisted in plaintext and cannot be
    # safely transformed without replaying device public-key delivery logic.
    # Delete the unshipped records before removing all plaintext columns.
    op.execute("DELETE FROM email_suggestions")
    op.drop_column("email_suggestions", "sender")
    op.drop_column("email_suggestions", "subject_sanitized")
    op.drop_column("email_suggestions", "body_sanitized")
    op.drop_column("email_suggestions", "status")
    op.create_table(
        "email_suggestion_deliveries",
        sa.Column(
            "suggestion_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("email_suggestions.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint("status IN ('pending', 'dismissed')", name="ck_email_delivery_status"),
    )
    op.create_index(
        "ix_email_deliveries_device_status",
        "email_suggestion_deliveries",
        ["device_id", "status"],
    )
    op.execute(
        "UPDATE schema_metadata SET value = '4', updated_at = now() WHERE key = 'schema_version'"
    )


def downgrade() -> None:
    op.execute("DELETE FROM email_suggestions")
    op.drop_table("email_suggestion_deliveries")
    op.add_column("email_suggestions", sa.Column("sender", sa.Text(), nullable=False))
    op.add_column("email_suggestions", sa.Column("subject_sanitized", sa.Text(), nullable=False))
    op.add_column("email_suggestions", sa.Column("body_sanitized", sa.Text(), nullable=False))
    op.add_column("email_suggestions", sa.Column("status", sa.Text(), nullable=False))
    op.execute(
        "UPDATE schema_metadata SET value = '3', updated_at = now() WHERE key = 'schema_version'"
    )
