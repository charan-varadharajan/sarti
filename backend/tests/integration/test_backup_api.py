import asyncio
import os
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import create_engine, select, update
from test_stage2_api import Api, StubWebAuthn

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import devices, families, family_backups, memberships
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def flow() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner = await api.register(str(uuid4()))
        stranger = await api.register(str(uuid4()))
        guardian = await api.register(str(uuid4()))
        created = await client.post("/v1/families", headers=api.headers(owner), json={})
        assert created.status_code == 201
        family_id = created.json()["id"]
        path = f"/v1/families/{family_id}/backup"
        headers = {**api.headers(owner), "X-Backup-Revision": "0"}
        blob = b"SART\x02" + os.urandom(150)
        assert (await client.get(path)).status_code == 401
        assert (await client.get(path, headers=api.headers(stranger))).status_code == 404
        assert (await client.put(path, headers=headers, content=b"plaintext")).status_code == 422
        assert (
            await client.put(path, headers=headers, content=b"SART\x01" + bytes(100))
        ).status_code == 422
        assert (
            await client.put(path, headers=headers, content=b"SART\x02" + bytes(10 * 1024 * 1024))
        ).status_code == 422
        assert (await client.put(path, headers=api.headers(owner), content=blob)).status_code == 422
        assert (await client.put(path, headers=headers, content=blob)).status_code == 204
        assert (await client.put(path, headers=headers, content=blob)).status_code == 409
        response = await client.get(path, headers=api.headers(owner))
        assert response.content == blob
        assert response.headers["cache-control"] == "no-store"
        assert response.headers["X-Backup-Revision"] == "1"
        assert (
            await client.put(path, headers={**headers, "X-Backup-Revision": "1"}, content=blob)
        ).status_code == 204
        engine = create_engine(url)
        with engine.begin() as connection:
            connection.execute(
                memberships.insert().values(
                    family_id=UUID(family_id),
                    adult_id=UUID(guardian["adult_id"]),
                    role="guardian",
                    status="active",
                    created_at=datetime.now(UTC),
                )
            )
        assert (await client.get(path, headers=api.headers(guardian))).status_code == 403
        assert (await client.delete(path, headers=api.headers(stranger))).status_code == 404
        assert (await client.delete(path, headers=api.headers(owner))).status_code == 204
        assert (await client.get(path, headers=api.headers(owner))).status_code == 404
        assert (await client.put(path, headers=headers, content=blob)).status_code == 204
        with engine.begin() as connection:
            connection.execute(
                update(devices)
                .where(devices.c.id == UUID(owner["device_id"]))
                .values(state="revoked")
            )
        assert (await client.get(path, headers=api.headers(owner))).status_code == 401
        with engine.begin() as connection:
            connection.execute(
                update(families)
                .where(families.c.id == UUID(family_id))
                .values(deleted_at=datetime.now(UTC))
            )
            assert (
                connection.execute(
                    select(family_backups).where(family_backups.c.family_id == UUID(family_id))
                ).first()
                is None
            )
        engine.dispose()
    database.close()


def test_backup_authorization_revision_and_deletion() -> None:
    asyncio.run(flow())
