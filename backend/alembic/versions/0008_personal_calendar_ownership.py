"""Explicit adult ownership for private calendar resources (ADR-038)."""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint("ck_resources_kind", "resources", type_="check")
    op.create_check_constraint(
        "ck_resources_kind",
        "resources",
        "kind IN ('family_profile','child_profile','calendar','personal_calendar','participant_profile')",
    )
    op.create_table(
        "personal_backups",
        sa.Column(
            "family_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "adult_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adults.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("revision", sa.BigInteger(), nullable=False),
        sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_check_constraint("ck_personal_backup_revision", "personal_backups", "revision > 0")
    op.create_check_constraint(
        "ck_personal_backup_size",
        "personal_backups",
        "octet_length(ciphertext) BETWEEN 94 AND 10485760",
    )
    op.execute("""CREATE FUNCTION purge_personal_backups() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.deleted_at IS NOT NULL THEN DELETE FROM personal_backups WHERE family_id=NEW.id; END IF;
      RETURN NEW;
    END $$;
    CREATE TRIGGER purge_personal_backups_on_delete AFTER UPDATE OF deleted_at ON families FOR EACH ROW EXECUTE FUNCTION purge_personal_backups();""")
    op.add_column("resources", sa.Column("private_adult_id", postgresql.UUID(as_uuid=True)))
    op.create_index(
        "uq_personal_calendar_adult",
        "resources",
        ["family_id", "private_adult_id"],
        unique=True,
        postgresql_where=sa.text("kind='personal_calendar' AND deleted_at IS NULL"),
    )
    op.create_check_constraint(
        "ck_resource_private_owner",
        "resources",
        "(kind = 'personal_calendar') = (private_adult_id IS NOT NULL)",
    )
    op.execute("UPDATE schema_metadata SET value='8', updated_at=now() WHERE key='schema_version'")


def downgrade() -> None:
    if (
        op.get_bind()
        .execute(
            sa.text(
                "SELECT 1 FROM resources WHERE kind IN ('personal_calendar','participant_profile') LIMIT 1"
            )
        )
        .first()
    ):
        raise RuntimeError("Cannot remove populated private calendar ownership.")
    if op.get_bind().execute(sa.text("SELECT 1 FROM personal_backups LIMIT 1")).first():
        raise RuntimeError("Cannot discard personal backups.")
    op.execute("DROP TRIGGER purge_personal_backups_on_delete ON families")
    op.execute("DROP FUNCTION purge_personal_backups()")
    op.drop_table("personal_backups")
    op.drop_index("uq_personal_calendar_adult", table_name="resources")
    op.drop_constraint("ck_resource_private_owner", "resources", type_="check")
    op.drop_column("resources", "private_adult_id")
    op.drop_constraint("ck_resources_kind", "resources", type_="check")
    op.create_check_constraint(
        "ck_resources_kind", "resources", "kind IN ('family_profile','child_profile','calendar')"
    )
    op.execute("UPDATE schema_metadata SET value='7', updated_at=now() WHERE key='schema_version'")
