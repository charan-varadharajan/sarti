"""BUG-011 version-tag contracts and ciphertext-preserving migration."""

import asyncio
import hashlib
import os
from uuid import UUID, uuid4

import pytest
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from test_stage2_api import Api, StubWebAuthn, b64

from alembic import command
from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import sync_operations
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def protocol_flow() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    # Isolated integration DB: migration exercise requires no v2 rows from
    # preceding fixture runs. No production database is used by the runner.
    with database.transaction() as c:
        c.execute(sync_operations.delete())
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        actor = await api.register(str(uuid4()))
        family = (await client.post("/v1/families", headers=api.headers(actor), json={})).json()
        resource = next(r["id"] for r in family["resources"] if r["kind"] == "calendar")
        nonce, ciphertext = os.urandom(24), os.urandom(64)
        payload = {
            "operation_id": str(uuid4()),
            "family_id": family["id"],
            "resource_id": resource,
            "device_sequence": 1,
            "key_epoch": 1,
            "logical_version": {actor["device_id"]: 1},
            "nonce": b64(nonce),
            "ciphertext": b64(ciphertext),
            "content_digest": b64(hashlib.sha256(nonce + ciphertext).digest()),
        }
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(actor), json=payload)
        ).status_code == 201
        config = Config("alembic.ini")
        command.downgrade(config, "0005")
        command.upgrade(config, "head")
        with database.connect() as c:
            row = (
                c.execute(
                    select(sync_operations).where(
                        sync_operations.c.operation_id == UUID(payload["operation_id"])
                    )
                )
                .mappings()
                .one()
            )
            assert (
                row["protocol_version"],
                row["nonce"],
                row["ciphertext"],
                row["content_digest"],
            ) == (1, nonce, ciphertext, hashlib.sha256(nonce + ciphertext).digest())
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(actor), json=payload)
        ).json()["duplicate"] is True
        new = dict(
            payload,
            operation_id=str(uuid4()),
            device_sequence=2,
            protocol_version=2,
            logical_version={str(uuid4()): 1, actor["device_id"]: 2},
        )
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(actor), json=new)
        ).status_code == 201
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(actor), json=new)
        ).json()["duplicate"] is True
        assert (
            await client.post(
                "/v1/sync/operations",
                headers=api.headers(actor),
                json=dict(new, protocol_version=1),
            )
        ).status_code == 409
        assert (
            await client.post(
                "/v1/sync/operations",
                headers=api.headers(actor),
                json=dict(new, protocol_version=3),
            )
        ).status_code == 422
        rows = (
            await client.get(f"/v1/families/{family['id']}/sync", headers=api.headers(actor))
        ).json()["operations"]
        assert [r["protocol_version"] for r in rows] == [1, 2]
        assert all(r["ciphertext"] == b64(ciphertext) for r in rows)
        with pytest.raises(RuntimeError, match="protocol-2 ciphertext"):
            command.downgrade(config, "0005")
    database.close()


def test_protocol_versions_retries_and_legacy_migration() -> None:
    asyncio.run(protocol_flow())
