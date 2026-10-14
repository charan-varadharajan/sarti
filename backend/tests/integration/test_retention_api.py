"""RETENTION-API/SEC-001: family policy is metadata, not event content."""

import asyncio
import os
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import create_engine, delete, update
from test_stage2_api import Api, StubWebAuthn

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import devices, families, memberships, permissions
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def flow() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    engine = create_engine(url)
    database = Database(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner = await api.register(str(uuid4()))
        guardian = await api.register(str(uuid4()))
        outsider = await api.register(str(uuid4()))
        family = (await client.post("/v1/families", headers=api.headers(owner), json={})).json()
        fid = UUID(family["id"])
        calendar = UUID(next(r["id"] for r in family["resources"] if r["kind"] == "calendar"))
        path = f"/v1/families/{fid}/calendar-retention"
        with engine.begin() as c:
            c.execute(
                memberships.insert().values(
                    family_id=fid,
                    adult_id=UUID(guardian["adult_id"]),
                    role="guardian",
                    status="active",
                    created_at=datetime.now(UTC),
                )
            )
            c.execute(
                permissions.insert().values(
                    resource_id=calendar, adult_id=UUID(guardian["adult_id"]), permission="write"
                )
            )
        try:
            assert (await client.get(path)).status_code == 401
            assert (await client.get(path, headers=api.headers(outsider))).status_code == 404
            default = (await client.get(path, headers=api.headers(owner))).json()
            assert default == {"period": "week", "enabled": True, "revision": 0, "can_manage": True}
            assert (await client.get(path, headers=api.headers(guardian))).json()[
                "can_manage"
            ] is False
            assert (
                await client.put(
                    path, headers=api.headers(guardian), json={"period": "never", "revision": 0}
                )
            ).status_code == 403
            assert (
                await client.put(
                    path, headers=api.headers(outsider), json={"period": "never", "revision": 0}
                )
            ).status_code == 404
            for body in (
                {"period": "forever", "revision": 0},
                {"period": "week", "revision": True},
                {"period": "week", "revision": -1},
                {"period": "week", "revision": 0, "title": "private"},
            ):
                assert (
                    await client.put(path, headers=api.headers(owner), json=body)
                ).status_code == 422
            with engine.begin() as c:
                c.execute(
                    permissions.update()
                    .where(permissions.c.resource_id == calendar)
                    .values(permission="admin")
                )
            for revision, period in enumerate(("month", "quarter", "year", "never", "week")):
                result = await client.put(
                    path,
                    headers=api.headers(guardian),
                    json={"period": period, "revision": revision},
                )
                assert result.status_code == 200
                assert result.json()["revision"] == revision + 1
                assert (await client.get(path, headers=api.headers(owner))).json()[
                    "period"
                ] == period
                assert (
                    await client.put(
                        path,
                        headers=api.headers(owner),
                        json={"period": "never", "revision": revision},
                    )
                ).status_code == 409
            with engine.begin() as c:
                c.execute(
                    update(memberships)
                    .where(
                        memberships.c.family_id == fid,
                        memberships.c.adult_id == UUID(guardian["adult_id"]),
                    )
                    .values(status="revoked")
                )
            assert (
                await client.put(
                    path, headers=api.headers(guardian), json={"period": "never", "revision": 5}
                )
            ).status_code == 404
            with engine.begin() as c:
                c.execute(
                    update(devices)
                    .where(devices.c.id == UUID(owner["device_id"]))
                    .values(state="revoked")
                )
            assert (
                await client.put(
                    path, headers=api.headers(owner), json={"period": "never", "revision": 5}
                )
            ).status_code == 401
        finally:
            # Independent task fixture: do not leave configured policies blocking downgrade tests.
            with engine.begin() as c:
                c.execute(delete(families).where(families.c.id == fid))
    engine.dispose()
    database.close()


def test_retention_api() -> None:
    asyncio.run(flow())
