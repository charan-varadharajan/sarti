"""Bounded operational maintenance; schedule regularly in a future deployment."""

import json
from datetime import UTC, datetime

from sqlalchemy import Connection, delete, func, select

from sarti_backend.core.config import get_settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import context_audit, sensitive_authorizations
from sarti_backend.households.expiry import expire_memberships


def maintain(connection: Connection) -> dict[str, int]:
    now = datetime.now(UTC)
    audit_count = int(
        connection.execute(
            select(func.count()).select_from(context_audit).where(context_audit.c.expires_at <= now)
        ).scalar_one()
    )
    proof_count = int(
        connection.execute(
            select(func.count())
            .select_from(sensitive_authorizations)
            .where(sensitive_authorizations.c.expires_at <= now)
        ).scalar_one()
    )
    expired = expire_memberships(connection)
    connection.execute(
        delete(sensitive_authorizations).where(sensitive_authorizations.c.expires_at <= now)
    )
    return {
        "expired_memberships": expired,
        "expired_audit_records": audit_count,
        "expired_confirmations": proof_count,
    }


def main() -> None:
    database = Database(get_settings().database_url)
    try:
        with database.transaction() as connection:
            counts = maintain(connection)
        # Counts only: no account/context identifiers, proofs or ciphertext.
        print(json.dumps(counts, sort_keys=True))
    finally:
        database.close()


if __name__ == "__main__":
    main()
