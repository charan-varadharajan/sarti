import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

metadata = sa.MetaData()

family_backups = sa.Table(
    "family_backups",
    metadata,
    sa.Column("family_id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("revision", sa.BigInteger(), nullable=False),
    sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
    sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
)

adults = sa.Table(
    "adults",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("webauthn_user_handle", sa.LargeBinary(), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
)

credentials = sa.Table(
    "webauthn_credentials",
    metadata,
    sa.Column("credential_id", sa.LargeBinary(), primary_key=True),
    sa.Column("adult_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("public_key", sa.LargeBinary(), nullable=False),
    sa.Column("sign_count", sa.BigInteger(), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
)

devices = sa.Table(
    "devices",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("adult_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("encryption_public_key", sa.LargeBinary(), nullable=False),
    sa.Column("signing_public_key", sa.LargeBinary(), nullable=False),
    sa.Column("state", sa.Text(), nullable=False),
    sa.Column("last_sync_sequence", sa.BigInteger(), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("revoked_at", sa.DateTime(timezone=True)),
    sa.Column("fcm_token", sa.Text()),
)

sessions = sa.Table(
    "sessions",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("token_digest", sa.LargeBinary(), nullable=False),
    sa.Column("adult_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("revoked_at", sa.DateTime(timezone=True)),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
)

challenges = sa.Table(
    "webauthn_challenges",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("kind", sa.Text(), nullable=False),
    sa.Column("challenge", sa.LargeBinary(), nullable=False),
    sa.Column("prospective_adult_id", postgresql.UUID(as_uuid=True)),
    sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("consumed_at", sa.DateTime(timezone=True)),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
)

families = sa.Table(
    "families",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("deleted_at", sa.DateTime(timezone=True)),
    sa.Column("email_token_digest", sa.LargeBinary()),
)

memberships = sa.Table(
    "memberships",
    metadata,
    sa.Column("family_id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("adult_id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("role", sa.Text(), nullable=False),
    sa.Column("status", sa.Text(), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("revoked_at", sa.DateTime(timezone=True)),
)

resources = sa.Table(
    "resources",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("kind", sa.Text(), nullable=False),
    sa.Column("key_epoch", sa.Integer(), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("deleted_at", sa.DateTime(timezone=True)),
)

permissions = sa.Table(
    "resource_permissions",
    metadata,
    sa.Column("resource_id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("adult_id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("permission", sa.Text(), nullable=False),
)

invitations = sa.Table(
    "guardian_invitations",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("inviter_adult_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("token_digest", sa.LargeBinary(), nullable=False),
    sa.Column("status", sa.Text(), nullable=False),
    sa.Column("accepted_by", postgresql.UUID(as_uuid=True)),
    sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("used_at", sa.DateTime(timezone=True)),
)

key_grants = sa.Table(
    "resource_key_grants",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("resource_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("key_epoch", sa.Integer(), nullable=False),
    sa.Column("recipient_device_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("granter_device_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("wrapped_key", sa.LargeBinary(), nullable=False),
    sa.Column("signature", sa.LargeBinary(), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
)

sync_operations = sa.Table(
    "sync_operations",
    metadata,
    sa.CheckConstraint("protocol_version IN (1, 2)", name="ck_sync_protocol_version"),
    sa.Column("protocol_version", sa.Integer(), nullable=False, server_default="1"),
    sa.Column("server_sequence", sa.BigInteger(), primary_key=True),
    sa.Column("operation_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("resource_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("author_device_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("device_sequence", sa.BigInteger(), nullable=False),
    sa.Column("key_epoch", sa.Integer(), nullable=False),
    sa.Column("logical_version", postgresql.JSONB(), nullable=False),
    sa.Column("nonce", sa.LargeBinary(), nullable=False),
    sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
    sa.Column("content_digest", sa.LargeBinary(), nullable=False),
    sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
)

email_suggestions = sa.Table(
    "email_suggestions",
    metadata,
    sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column("content_digest", sa.LargeBinary(), nullable=False),
    sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
    sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
)

email_suggestion_deliveries = sa.Table(
    "email_suggestion_deliveries",
    metadata,
    sa.Column("suggestion_id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("device_id", postgresql.UUID(as_uuid=True), primary_key=True),
    sa.Column("ciphertext", sa.LargeBinary(), nullable=False),
    sa.Column("status", sa.Text(), nullable=False),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
)
