"""Add Stage 3 columns and email_suggestions table.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-12
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("devices", sa.Column("fcm_token", sa.Text(), nullable=True))
    op.add_column(
        "families", sa.Column("email_token_digest", sa.LargeBinary(), nullable=True)
    )
    op.create_index(
        "uq_families_email_token",
        "families",
        ["email_token_digest"],
        unique=True,
        postgresql_where=sa.text("email_token_digest IS NOT NULL"),
    )
    op.create_table(
        "email_suggestions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "family_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("sender", sa.Text(), nullable=False),
        sa.Column("subject_sanitized", sa.Text(), nullable=False),
        sa.Column("body_sanitized", sa.Text(), nullable=False),
        sa.Column("content_digest", sa.LargeBinary(), nullable=False, unique=True),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column(
            "received_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "status IN ('pending', 'approved', 'dismissed')",
            name="ck_email_suggestions_status",
        ),
    )
    op.create_index(
        "ix_email_suggestions_family_received",
        "email_suggestions",
        ["family_id", "received_at"],
    )
    op.create_index("ix_email_suggestions_expiry", "email_suggestions", ["expires_at"])
    op.execute(
        "UPDATE schema_metadata SET value = '3', updated_at = now() WHERE key = 'schema_version'"
    )


def downgrade() -> None:
    op.drop_table("email_suggestions")
    op.drop_index("uq_families_email_token", table_name="families")
    op.drop_column("families", "email_token_digest")
    op.drop_column("devices", "fcm_token")
    op.execute(
        "UPDATE schema_metadata SET value = '2', updated_at = now() WHERE key = 'schema_version'"
    )
