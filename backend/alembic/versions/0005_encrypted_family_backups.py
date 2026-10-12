"""Opaque family backup snapshots, separate from expiring sync relay."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "family_backups",
        sa.Column(
            "family_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("revision", sa.BigInteger(), nullable=False),
        sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("revision > 0", name="ck_backup_revision"),
        sa.CheckConstraint(
            "octet_length(ciphertext) BETWEEN 94 AND 10485760", name="ck_backup_size"
        ),
    )
    op.execute(
        "UPDATE schema_metadata SET value = '5', updated_at = now() WHERE key = 'schema_version'"
    )
    op.execute("""
        CREATE FUNCTION purge_family_backup() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          IF NEW.deleted_at IS NOT NULL THEN
            DELETE FROM family_backups WHERE family_id = NEW.id;
          END IF;
          RETURN NEW;
        END $$;
        CREATE TRIGGER purge_family_backup_on_delete
          AFTER UPDATE OF deleted_at ON families
          FOR EACH ROW EXECUTE FUNCTION purge_family_backup();
    """)


def downgrade() -> None:
    op.execute("DROP TRIGGER purge_family_backup_on_delete ON families")
    op.execute("DROP FUNCTION purge_family_backup()")
    op.drop_table("family_backups")
    op.execute(
        "UPDATE schema_metadata SET value = '4', updated_at = now() WHERE key = 'schema_version'"
    )
