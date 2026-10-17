"""Encrypted administrative audit resources (ADR-041)."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

KINDS = "'family_profile','child_profile','calendar','personal_calendar','participant_profile','admin_audit','care_calendar','classroom_calendar','activity_calendar','school_calendar'"


def upgrade() -> None:
    op.drop_constraint("ck_resources_kind", "resources")
    op.create_check_constraint("ck_resources_kind", "resources", f"kind IN ({KINDS})")
    op.create_table(
        "context_audit",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "family_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "resource_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("resources.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("actor_device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("action", sa.Text(), nullable=False),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("acl_revision", sa.BigInteger(), nullable=False),
        sa.Column("envelope", postgresql.JSONB(), nullable=False),
        sa.Column("request_digest", sa.LargeBinary(), nullable=False),
        sa.Column("outcome", postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_context_audit_expiry", "context_audit", ["expires_at"])
    op.execute("UPDATE schema_metadata SET value='13',updated_at=now() WHERE key='schema_version'")


def downgrade() -> None:
    op.execute(
        "DO $$ BEGIN IF EXISTS(SELECT 1 FROM context_audit) OR EXISTS(SELECT 1 FROM resources WHERE kind IN ('admin_audit','care_calendar','classroom_calendar','activity_calendar','school_calendar')) THEN RAISE EXCEPTION 'cannot discard scoped resources/audit'; END IF; END $$"
    )
    op.drop_table("context_audit")
    op.drop_constraint("ck_resources_kind", "resources")
    op.create_check_constraint(
        "ck_resources_kind",
        "resources",
        "kind IN ('family_profile','child_profile','calendar','personal_calendar','participant_profile')",
    )
    op.execute("UPDATE schema_metadata SET value='12',updated_at=now() WHERE key='schema_version'")
