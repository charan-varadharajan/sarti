"""Operation-bound current-device reauthentication (ADR-041)."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "families", sa.Column("acl_revision", sa.BigInteger(), nullable=False, server_default="0")
    )
    op.create_check_constraint("ck_family_acl_revision", "families", "acl_revision >= 0")
    op.create_table(
        "sensitive_authorizations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("action", sa.Text(), nullable=False),
        sa.Column(
            "family_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("families.id", ondelete="CASCADE"),
        ),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("acl_revision", sa.BigInteger(), nullable=False),
        sa.Column("challenge", sa.LargeBinary(), nullable=False),
        sa.Column("proof_digest", sa.LargeBinary(), unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("verified_at", sa.DateTime(timezone=True)),
        sa.Column("consumed_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("acl_revision >= 0", name="ck_sensitive_acl_revision"),
        sa.CheckConstraint("octet_length(challenge) = 32", name="ck_sensitive_challenge"),
        sa.CheckConstraint(
            "proof_digest IS NULL OR octet_length(proof_digest) = 32", name="ck_sensitive_proof"
        ),
    )
    op.create_index("ix_sensitive_expiry", "sensitive_authorizations", ["expires_at"])
    op.execute("UPDATE schema_metadata SET value='11',updated_at=now() WHERE key='schema_version'")


def downgrade() -> None:
    op.drop_table("sensitive_authorizations")
    op.drop_constraint("ck_family_acl_revision", "families")
    op.drop_column("families", "acl_revision")
    op.execute("UPDATE schema_metadata SET value='10',updated_at=now() WHERE key='schema_version'")
