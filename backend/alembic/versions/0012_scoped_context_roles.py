"""Context roles and explicit migrated administrator grants (ADR-041)."""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "families", sa.Column("context_kind", sa.Text(), nullable=False, server_default="household")
    )
    op.create_check_constraint(
        "ck_context_kind",
        "families",
        "context_kind IN ('household','classroom','activity','school')",
    )
    op.add_column("memberships", sa.Column("expires_at", sa.DateTime(timezone=True)))
    op.drop_constraint("ck_memberships_role", "memberships")
    op.create_check_constraint(
        "ck_memberships_role",
        "memberships",
        "role IN ('owner','administrator','guardian','limited_caregiver','teacher','parent_volunteer','classroom_administrator','school_administrator','school_calendar_subscriber')",
    )
    # Materialize exactly existing owner authority; never grant private resources.
    op.execute(
        "INSERT INTO resource_permissions(resource_id,adult_id,permission) SELECT r.id,m.adult_id,'admin' FROM resources r JOIN memberships m ON m.family_id=r.family_id WHERE m.role='owner' AND m.status='active' AND r.deleted_at IS NULL AND r.private_adult_id IS NULL ON CONFLICT(resource_id,adult_id) DO UPDATE SET permission='admin'"
    )
    op.execute("UPDATE memberships SET role='administrator' WHERE role='owner'")
    op.execute("UPDATE schema_metadata SET value='12',updated_at=now() WHERE key='schema_version'")


def downgrade() -> None:
    op.execute(
        "DO $$ BEGIN IF EXISTS(SELECT 1 FROM families WHERE context_kind<>'household') OR EXISTS(SELECT 1 FROM memberships WHERE role NOT IN ('owner','administrator','guardian') OR expires_at IS NOT NULL) OR EXISTS(SELECT family_id FROM memberships WHERE role='administrator' AND status='active' GROUP BY family_id HAVING count(*)>1) THEN RAISE EXCEPTION 'scoped context downgrade would lose permissions'; END IF; END $$"
    )
    # Legacy owners implicitly read every public resource. Refuse to turn a
    # deliberately scoped administrator into such an owner on rollback.
    op.execute(
        "DO $$ BEGIN IF EXISTS(SELECT 1 FROM memberships m JOIN resources r ON r.family_id=m.family_id AND r.deleted_at IS NULL AND r.private_adult_id IS NULL WHERE m.role='administrator' AND m.status='active' AND NOT EXISTS(SELECT 1 FROM resource_permissions p WHERE p.resource_id=r.id AND p.adult_id=m.adult_id AND p.permission='admin')) THEN RAISE EXCEPTION 'scoped administrator downgrade would escalate access'; END IF; END $$"
    )
    op.execute("UPDATE memberships SET role='owner' WHERE role='administrator'")
    op.drop_constraint("ck_memberships_role", "memberships")
    op.create_check_constraint("ck_memberships_role", "memberships", "role IN ('owner','guardian')")
    op.drop_column("memberships", "expires_at")
    op.drop_constraint("ck_context_kind", "families")
    op.drop_column("families", "context_kind")
    op.execute("UPDATE schema_metadata SET value='11',updated_at=now() WHERE key='schema_version'")
