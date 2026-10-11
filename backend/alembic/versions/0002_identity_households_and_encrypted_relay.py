"""Create identity, household authorization, key grant, and relay metadata.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-11
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "adults",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("webauthn_user_handle", sa.LargeBinary(), nullable=False, unique=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_table(
        "webauthn_credentials",
        sa.Column("credential_id", sa.LargeBinary(), primary_key=True),
        sa.Column(
            "adult_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adults.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("public_key", sa.LargeBinary(), nullable=False),
        sa.Column("sign_count", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("ix_webauthn_credentials_adult", "webauthn_credentials", ["adult_id"])
    op.create_table(
        "devices",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "adult_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adults.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("encryption_public_key", sa.LargeBinary(), nullable=False),
        sa.Column("signing_public_key", sa.LargeBinary(), nullable=False),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("last_sync_sequence", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("state IN ('active', 'revoked')", name="ck_devices_state"),
        sa.CheckConstraint(
            "octet_length(encryption_public_key) = 32", name="ck_devices_encryption_key"
        ),
        sa.CheckConstraint("octet_length(signing_public_key) = 32", name="ck_devices_signing_key"),
    )
    op.create_index("ix_devices_adult", "devices", ["adult_id"])
    op.create_index(
        "uq_devices_one_active_phone_per_adult",
        "devices",
        ["adult_id"],
        unique=True,
        postgresql_where=sa.text("state = 'active'"),
    )
    op.create_table(
        "sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("token_digest", sa.LargeBinary(), nullable=False, unique=True),
        sa.Column(
            "adult_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adults.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("ix_sessions_lookup", "sessions", ["token_digest", "expires_at"])
    op.create_table(
        "webauthn_challenges",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("challenge", sa.LargeBinary(), nullable=False),
        sa.Column("prospective_adult_id", postgresql.UUID(as_uuid=True)),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint("kind IN ('registration', 'authentication')", name="ck_challenges_kind"),
    )
    op.create_index("ix_challenges_expiry", "webauthn_challenges", ["expires_at"])
    op.create_table(
        "families",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("adults.id"), nullable=False
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "memberships",
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
        sa.Column("role", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("role IN ('owner', 'guardian')", name="ck_memberships_role"),
        sa.CheckConstraint(
            "status IN ('pending', 'active', 'revoked')", name="ck_memberships_status"
        ),
    )
    op.create_index("ix_memberships_adult", "memberships", ["adult_id", "status"])
    op.create_table(
        "resources",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "family_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("key_epoch", sa.Integer(), nullable=False, server_default="1"),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint(
            "kind IN ('family_profile', 'child_profile', 'calendar')", name="ck_resources_kind"
        ),
        sa.CheckConstraint("key_epoch > 0", name="ck_resources_key_epoch"),
    )
    op.create_index("ix_resources_family", "resources", ["family_id"])
    op.create_table(
        "resource_permissions",
        sa.Column(
            "resource_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("resources.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "adult_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adults.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("permission", sa.Text(), nullable=False),
        sa.CheckConstraint(
            "permission IN ('read', 'write', 'admin')", name="ck_resource_permissions_value"
        ),
    )
    op.create_table(
        "guardian_invitations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "family_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("families.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "inviter_adult_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adults.id"),
            nullable=False,
        ),
        sa.Column("token_digest", sa.LargeBinary(), nullable=False, unique=True),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("accepted_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("adults.id")),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("used_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint(
            "status IN ('open', 'pending', 'approved', 'revoked')", name="ck_invitations_status"
        ),
    )
    op.create_index("ix_invitations_family", "guardian_invitations", ["family_id"])
    op.create_table(
        "resource_key_grants",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "resource_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("resources.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("key_epoch", sa.Integer(), nullable=False),
        sa.Column(
            "recipient_device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "granter_device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id"),
            nullable=False,
        ),
        sa.Column("wrapped_key", sa.LargeBinary(), nullable=False),
        sa.Column("signature", sa.LargeBinary(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.UniqueConstraint(
            "resource_id", "key_epoch", "recipient_device_id", name="uq_key_grant_recipient_epoch"
        ),
        sa.CheckConstraint(
            "octet_length(wrapped_key) BETWEEN 48 AND 512", name="ck_key_grants_wrapped_size"
        ),
        sa.CheckConstraint("octet_length(signature) = 64", name="ck_key_grants_signature"),
    )
    op.create_table(
        "sync_operations",
        sa.Column("server_sequence", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("operation_id", postgresql.UUID(as_uuid=True), nullable=False, unique=True),
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
        sa.Column(
            "author_device_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("devices.id"),
            nullable=False,
        ),
        sa.Column("device_sequence", sa.BigInteger(), nullable=False),
        sa.Column("key_epoch", sa.Integer(), nullable=False),
        sa.Column("logical_version", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("nonce", sa.LargeBinary(), nullable=False),
        sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("content_digest", sa.LargeBinary(), nullable=False),
        sa.Column(
            "received_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("author_device_id", "device_sequence", name="uq_sync_device_sequence"),
        sa.CheckConstraint("device_sequence > 0", name="ck_sync_device_sequence"),
        sa.CheckConstraint("octet_length(nonce) = 24", name="ck_sync_nonce"),
        sa.CheckConstraint(
            "octet_length(ciphertext) BETWEEN 17 AND 1048592", name="ck_sync_ciphertext_size"
        ),
        sa.CheckConstraint("octet_length(content_digest) = 32", name="ck_sync_digest"),
    )
    op.create_index("ix_sync_family_cursor", "sync_operations", ["family_id", "server_sequence"])
    op.create_index("ix_sync_expiry", "sync_operations", ["expires_at"])
    op.execute(
        "UPDATE schema_metadata SET value = '2', updated_at = now() WHERE key = 'schema_version'"
    )


def downgrade() -> None:
    for table in (
        "sync_operations",
        "resource_key_grants",
        "guardian_invitations",
        "resource_permissions",
        "resources",
        "memberships",
        "families",
        "webauthn_challenges",
        "sessions",
        "devices",
        "webauthn_credentials",
        "adults",
    ):
        op.drop_table(table)
    op.execute(
        "UPDATE schema_metadata SET value = '1', updated_at = now() WHERE key = 'schema_version'"
    )
